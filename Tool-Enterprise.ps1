$null = try { Add-Type -AssemblyName System.Security -ErrorAction Stop } catch { $null }

$script:ToolEnterpriseSchemaVersion = "1.0"
$script:ToolEnterpriseProtocolVersion = "1.0"
$script:ToolEnterpriseToolVersion = "4.3"
$script:ToolEnterpriseDefaultPort = 49420
$script:ToolEnterpriseMaximumRequestBytes = 1048576
$script:ToolEnterpriseMaximumScanHosts = 1024
$script:ToolEnterpriseInitializedRoot = ""
$script:ToolEnterpriseInitializedPaths = $null

function ConvertTo-ToolEnterpriseSafeText {
    param([AllowNull()][object]$Value, [int]$MaximumLength = 2048)

    if ($null -eq $Value) { return "" }
    $text = ([string]$Value).Replace("`0", "").Replace("`r", " ").Replace("`n", " ").Trim()
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}(?![A-Z0-9])', 'XXXXX-XXXXX-XXXXX-XXXXX-[ĐÃ CHE]')
    $text = [regex]::Replace($text, '(?i)(?<![A-Z0-9])[A-Z0-9]{25}(?![A-Z0-9])', '[ĐÃ CHE PRODUCT KEY]')
    if ($text.Length -gt $MaximumLength) { return $text.Substring(0, $MaximumLength) }
    return $text
}

function Get-ToolEnterpriseRoot {
    $configured = [string]$env:TOOL_ENTERPRISE_ROOT
    if (-not [string]::IsNullOrWhiteSpace($configured)) { return [IO.Path]::GetFullPath($configured) }
    $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    return (Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\v4.3\enterprise")
}

function Get-ToolEnterprisePaths {
    $root = Get-ToolEnterpriseRoot
    return [pscustomobject][ordered]@{
        Root = $root
        Server = Join-Path $root "server"
        ServerConfig = Join-Path $root "server\server.json"
        ServerMasterSecret = Join-Path $root "server\server-master.bin"
        ServerPairingSecret = Join-Path $root "server\pairing-secret.bin"
        ServerClients = Join-Path $root "server\clients"
        ServerClientSecrets = Join-Path $root "server\client-secrets"
        ServerReports = Join-Path $root "server\reports"
        ServerJobs = Join-Path $root "server\jobs"
        ServerResults = Join-Path $root "server\results"
        ServerAudit = Join-Path $root "server\enterprise-audit.jsonl"
        ServerPid = Join-Path $root "server\server.pid.json"
        ServerHeartbeat = Join-Path $root "server\server-heartbeat.json"
        ServerStop = Join-Path $root "server\server.stop"
        ServerError = Join-Path $root "server\server-error.json"
        Client = Join-Path $root "client"
        ClientConfig = Join-Path $root "client\client.json"
        ClientSecret = Join-Path $root "client\client-secret.bin"
        ClientOutbox = Join-Path $root "client\outbox"
        ClientProcessed = Join-Path $root "client\processed"
        ClientAudit = Join-Path $root "client\enterprise-audit.jsonl"
        Bin = Join-Path $root "bin"
    }
}

function Test-ToolEnterpriseReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool]((Get-Item -LiteralPath $Path -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Set-ToolEnterpriseProtectedDirectoryAcl {
    param([Parameter(Mandatory = $true)][string]$Path)

    # Test harnesses can point the root at an isolated temporary directory.
    # Never set this variable in a deployed build; the launcher does not set
    # it and therefore always applies the protected ACL.
    if ([string]$env:TOOL_ENTERPRISE_SKIP_ACL -eq "1") { return }

    $administratorsSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-32-544")
    $systemSid = New-Object Security.Principal.SecurityIdentifier("S-1-5-18")
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    # Setting the owner requires SeRestorePrivilege on some locked-down
    # Windows images and causes Set-Acl to fail even for an administrator
    # token.  Keep the existing owner and protect the directory with the
    # explicit DACL instead.
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($administratorsSid, "FullControl", $inheritance, "None", "Allow")))
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($systemSid, "FullControl", $inheritance, "None", "Allow")))
    try {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($currentSid) {
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($currentSid, "FullControl", $inheritance, "None", "Allow")))
        }
    } catch { }
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Initialize-ToolEnterpriseStorage {
    $paths = Get-ToolEnterprisePaths
    if ($script:ToolEnterpriseInitializedPaths -and
        [string]::Equals([string]$script:ToolEnterpriseInitializedRoot, [string]$paths.Root, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $paths.Root -PathType Container)) {
        return $script:ToolEnterpriseInitializedPaths
    }
    $rootExisted = Test-Path -LiteralPath $paths.Root -PathType Container
    $directories = @(
        $paths.Root, $paths.Server, $paths.ServerClients, $paths.ServerClientSecrets,
        $paths.ServerReports, $paths.ServerJobs, $paths.ServerResults,
        $paths.Client, $paths.ClientOutbox, $paths.ClientProcessed, $paths.Bin
    )
    foreach ($directory in $directories) {
        if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw "Từ chối thư mục enterprise là junction/symlink: $directory" }
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
        if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw "Từ chối thư mục enterprise là junction/symlink: $directory" }
    }
    # The one-file launcher has already created and locked the v4.3 root.
    # Avoid re-applying an ACL on every inventory/report call (it is both
    # expensive and can require SeSecurityPrivilege on hardened images).
    # For a newly-created source/standalone root, apply it once; secure launch
    # remains fail-closed if that initial protection cannot be established.
    if (-not $rootExisted -or [string]$env:TOOL_ENTERPRISE_FORCE_ACL -eq "1") {
        try { Set-ToolEnterpriseProtectedDirectoryAcl -Path $paths.Root }
        catch {
            if ([string]$env:TOOL_SECURE_LAUNCH -eq "1") { throw }
        }
    }
    $script:ToolEnterpriseInitializedRoot = [string]$paths.Root
    $script:ToolEnterpriseInitializedPaths = $paths
    return $paths
}

function Assert-ToolEnterprisePath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $root = [IO.Path]::GetFullPath((Get-ToolEnterpriseRoot)).TrimEnd('\') + '\'
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($root, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Đường dẫn nằm ngoài vùng enterprise được bảo vệ: $full"
    }
    return $full
}

function Write-ToolEnterpriseJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Value
    )

    $full = Assert-ToolEnterprisePath -Path $Path
    $directory = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw "Từ chối ghi vào thư mục reparse point: $directory" }
    if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $full)) {
        throw "Từ chối ghi đè tệp enterprise là reparse point: $full"
    }
    $temporary = Join-Path $directory (".write-" + [Guid]::NewGuid().ToString("N") + ".tmp")
    $json = $Value | ConvertTo-Json -Depth 14
    [IO.File]::WriteAllText($temporary, $json, (New-Object Text.UTF8Encoding($false)))
    try {
        Move-Item -LiteralPath $temporary -Destination $full -Force
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Read-ToolEnterpriseJson {
    param([Parameter(Mandatory = $true)][string]$Path, [int]$MaximumBytes = 10485760)

    $full = Assert-ToolEnterprisePath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Từ chối đọc tệp enterprise là reparse point: $full" }
    if ($item.Length -le 0 -or $item.Length -gt $MaximumBytes) { throw "Tệp JSON enterprise rỗng hoặc vượt giới hạn: $full" }
    return (Get-Content -LiteralPath $full -Raw -ErrorAction Stop | ConvertFrom-Json)
}

function Get-ToolEnterpriseSha256Bytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return $algorithm.ComputeHash($Bytes) } finally { $algorithm.Dispose() }
}

function Get-ToolEnterpriseSha256Hex {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $algorithm = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace("-", "") }
        finally { $algorithm.Dispose() }
    } finally { $stream.Dispose() }
}

function New-ToolEnterpriseRandomBytes {
    param([ValidateRange(16, 128)][int]$Length = 32)
    $bytes = New-Object byte[] $Length
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    return $bytes
}

function ConvertTo-ToolEnterpriseBase64Url {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function ConvertFrom-ToolEnterpriseBase64Url {
    param([Parameter(Mandatory = $true)][string]$Text)
    if ($Text -notmatch '^[A-Za-z0-9_-]+$') { throw "Chuỗi base64url không hợp lệ." }
    $normalized = $Text.Replace('-', '+').Replace('_', '/')
    while (($normalized.Length % 4) -ne 0) { $normalized += '=' }
    return [Convert]::FromBase64String($normalized)
}

function Get-ToolEnterpriseDpapiEntropy {
    return (Get-ToolEnterpriseSha256Bytes -Bytes ([Text.Encoding]::UTF8.GetBytes("ThanhViet-Tool-Kiem-Tra-v4.3-enterprise")))
}

function Protect-ToolEnterpriseBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Security.Cryptography.ProtectedData]::Protect(
        $Bytes,
        (Get-ToolEnterpriseDpapiEntropy),
        [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
}

function Unprotect-ToolEnterpriseBytes {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    return [Security.Cryptography.ProtectedData]::Unprotect(
        $Bytes,
        (Get-ToolEnterpriseDpapiEntropy),
        [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
}

function Set-ToolEnterpriseSecret {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][byte[]]$Secret)
    $full = Assert-ToolEnterprisePath -Path $Path
    $directory = Split-Path -Parent $full
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
    if (Test-ToolEnterpriseReparsePoint -Path $directory) { throw "Từ chối ghi secret vào thư mục reparse point." }
    if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $full)) { throw "Từ chối ghi đè secret là reparse point." }
    $protected = Protect-ToolEnterpriseBytes -Bytes $Secret
    $temporary = Join-Path $directory (".secret-" + [Guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [IO.File]::WriteAllBytes($temporary, $protected)
        Move-Item -LiteralPath $temporary -Destination $full -Force
    } finally {
        if ($protected) { [Array]::Clear($protected, 0, $protected.Length) }
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Get-ToolEnterpriseSecret {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = Assert-ToolEnterprisePath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $null }
    $item = Get-Item -LiteralPath $full -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Tệp secret không được là reparse point." }
    if ($item.Length -le 0 -or $item.Length -gt 65536) { throw "Tệp secret rỗng hoặc vượt giới hạn." }
    return (Unprotect-ToolEnterpriseBytes -Bytes ([IO.File]::ReadAllBytes($full)))
}

function Get-ToolEnterpriseDerivedKey {
    param([Parameter(Mandatory = $true)][byte[]]$Secret, [Parameter(Mandatory = $true)][string]$Purpose)
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$Secret)
    try { return $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes("v4.3-enterprise|" + $Purpose)) }
    finally { $hmac.Dispose() }
}

function Test-ToolEnterpriseFixedTimeEquals {
    param([Parameter(Mandatory = $true)][byte[]]$Left, [Parameter(Mandatory = $true)][byte[]]$Right)
    if ($Left.Length -ne $Right.Length) { return $false }
    $difference = 0
    for ($index = 0; $index -lt $Left.Length; $index++) {
        $difference = $difference -bor ($Left[$index] -bxor $Right[$index])
    }
    return [bool]($difference -eq 0)
}

function New-ToolEnterpriseEnvelope {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Secret,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][AllowNull()][object]$Payload
    )

    $safeContext = ConvertTo-ToolEnterpriseSafeText $Context 180
    if ([string]::IsNullOrWhiteSpace($safeContext)) { throw "Context mã hóa không hợp lệ." }
    $plainJson = $Payload | ConvertTo-Json -Depth 14 -Compress
    $plainBytes = [Text.Encoding]::UTF8.GetBytes($plainJson)
    if ($plainBytes.Length -gt $script:ToolEnterpriseMaximumRequestBytes) { throw "Payload enterprise vượt giới hạn 1 MB." }
    $encryptionKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "encryption"
    $authenticationKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "authentication"
    $aes = New-Object Security.Cryptography.AesManaged
    try {
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encryptionKey
        $aes.GenerateIV()
        $encryptor = $aes.CreateEncryptor()
        try { $cipherBytes = $encryptor.TransformFinalBlock($plainBytes, 0, $plainBytes.Length) }
        finally { $encryptor.Dispose() }
        $timestamp = [DateTime]::UtcNow.ToString("o")
        $nonce = ConvertTo-ToolEnterpriseBase64Url -Bytes (New-ToolEnterpriseRandomBytes -Length 18)
        $iv = ConvertTo-ToolEnterpriseBase64Url -Bytes $aes.IV
        $cipherText = ConvertTo-ToolEnterpriseBase64Url -Bytes $cipherBytes
        $canonical = "$($script:ToolEnterpriseProtocolVersion)`n$safeContext`n$timestamp`n$nonce`n$iv`n$cipherText"
        $hmac = New-Object Security.Cryptography.HMACSHA256(,$authenticationKey)
        try { $mac = ConvertTo-ToolEnterpriseBase64Url -Bytes ($hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical))) }
        finally { $hmac.Dispose() }
        return [pscustomobject][ordered]@{
            ProtocolVersion = $script:ToolEnterpriseProtocolVersion
            Context = $safeContext
            TimestampUtc = $timestamp
            Nonce = $nonce
            Iv = $iv
            CipherText = $cipherText
            Mac = $mac
        }
    } finally {
        $aes.Dispose()
        [Array]::Clear($plainBytes, 0, $plainBytes.Length)
        [Array]::Clear($encryptionKey, 0, $encryptionKey.Length)
        [Array]::Clear($authenticationKey, 0, $authenticationKey.Length)
    }
}

function Open-ToolEnterpriseEnvelope {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Secret,
        [Parameter(Mandatory = $true)][string]$ExpectedContext,
        [Parameter(Mandatory = $true)][object]$Envelope,
        [ValidateRange(1, 10080)][int]$MaximumAgeMinutes = 10
    )

    foreach ($propertyName in @("ProtocolVersion", "Context", "TimestampUtc", "Nonce", "Iv", "CipherText", "Mac")) {
        if ($null -eq $Envelope.PSObject.Properties[$propertyName] -or [string]::IsNullOrWhiteSpace([string]$Envelope.$propertyName)) {
            throw "Envelope thiếu trường bắt buộc: $propertyName"
        }
    }
    if ([string]$Envelope.ProtocolVersion -ne $script:ToolEnterpriseProtocolVersion) { throw "ProtocolVersion không được hỗ trợ." }
    if (-not [string]::Equals([string]$Envelope.Context, $ExpectedContext, [StringComparison]::Ordinal)) { throw "Context envelope không khớp." }
    $timestamp = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Envelope.TimestampUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind, [ref]$timestamp)) {
        throw "Timestamp envelope không hợp lệ."
    }
    $age = [DateTime]::UtcNow - $timestamp.ToUniversalTime()
    if ([Math]::Abs($age.TotalMinutes) -gt $MaximumAgeMinutes) { throw "Envelope đã hết hạn hoặc thời gian hai máy sai lệch quá lớn." }
    $authenticationKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "authentication"
    $canonical = "$([string]$Envelope.ProtocolVersion)`n$([string]$Envelope.Context)`n$([string]$Envelope.TimestampUtc)`n$([string]$Envelope.Nonce)`n$([string]$Envelope.Iv)`n$([string]$Envelope.CipherText)"
    $hmac = New-Object Security.Cryptography.HMACSHA256(,$authenticationKey)
    try { $expectedMac = $hmac.ComputeHash([Text.Encoding]::UTF8.GetBytes($canonical)) }
    finally { $hmac.Dispose(); [Array]::Clear($authenticationKey, 0, $authenticationKey.Length) }
    $actualMac = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Envelope.Mac)
    if (-not (Test-ToolEnterpriseFixedTimeEquals -Left $expectedMac -Right $actualMac)) { throw "HMAC envelope không hợp lệ." }
    $encryptionKey = Get-ToolEnterpriseDerivedKey -Secret $Secret -Purpose "encryption"
    $iv = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Envelope.Iv)
    $cipherBytes = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Envelope.CipherText)
    $aes = New-Object Security.Cryptography.AesManaged
    try {
        $aes.KeySize = 256
        $aes.BlockSize = 128
        $aes.Mode = [Security.Cryptography.CipherMode]::CBC
        $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7
        $aes.Key = $encryptionKey
        $aes.IV = $iv
        $decryptor = $aes.CreateDecryptor()
        try { $plainBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length) }
        finally { $decryptor.Dispose() }
        if ($plainBytes.Length -gt $script:ToolEnterpriseMaximumRequestBytes) { throw "Payload giải mã vượt giới hạn." }
        $plainJson = [Text.Encoding]::UTF8.GetString($plainBytes)
        $payload = $plainJson | ConvertFrom-Json
        return [pscustomobject][ordered]@{
            Payload = $payload
            Nonce = [string]$Envelope.Nonce
            TimestampUtc = $timestamp.ToUniversalTime()
        }
    } finally {
        $aes.Dispose()
        [Array]::Clear($encryptionKey, 0, $encryptionKey.Length)
        if ($plainBytes) { [Array]::Clear($plainBytes, 0, $plainBytes.Length) }
    }
}

function New-ToolEnterpriseAdminVerifier {
    param([Parameter(Mandatory = $true)][string]$AdminCode)
    if ($AdminCode.Length -lt 8 -or $AdminCode.Length -gt 128) { throw "Mã quản trị máy chủ phải từ 8 đến 128 ký tự." }
    $salt = New-ToolEnterpriseRandomBytes -Length 24
    $derive = New-Object Security.Cryptography.Rfc2898DeriveBytes($AdminCode, $salt, 120000)
    try { $hash = $derive.GetBytes(32) } finally { $derive.Dispose() }
    return [pscustomobject][ordered]@{
        Algorithm = "PBKDF2-HMAC-SHA1"
        Iterations = 120000
        Salt = ConvertTo-ToolEnterpriseBase64Url -Bytes $salt
        Hash = ConvertTo-ToolEnterpriseBase64Url -Bytes $hash
    }
}

function Test-ToolEnterpriseAdminCode {
    param([Parameter(Mandatory = $true)][string]$AdminCode, [Parameter(Mandatory = $true)][object]$Verifier)
    try {
        $salt = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Verifier.Salt)
        $expected = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$Verifier.Hash)
        $iterations = [int]$Verifier.Iterations
        if ($iterations -lt 100000) { return $false }
        $derive = New-Object Security.Cryptography.Rfc2898DeriveBytes($AdminCode, $salt, $iterations)
        try { $actual = $derive.GetBytes($expected.Length) } finally { $derive.Dispose() }
        return (Test-ToolEnterpriseFixedTimeEquals -Left $expected -Right $actual)
    } catch { return $false }
}

function Write-ToolEnterpriseAudit {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("Server", "Client")][string]$Scope,
        [Parameter(Mandatory = $true)][string]$Event,
        [string]$Message = "",
        [AllowNull()][object]$Data = $null
    )

    $paths = Initialize-ToolEnterpriseStorage
    $auditCandidate = if ($Scope -eq "Server") { $paths.ServerAudit } else { $paths.ClientAudit }
    $path = Assert-ToolEnterprisePath -Path $auditCandidate
    $auditDirectory = Split-Path -Parent $path
    if (Test-ToolEnterpriseReparsePoint -Path $auditDirectory) {
        throw "Từ chối ghi audit vào thư mục reparse point: $auditDirectory"
    }
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $path)) {
        throw "Từ chối ghi đè audit là reparse point: $path"
    }
    $record = [ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        TimestampUtc = [DateTime]::UtcNow.ToString("o")
        Scope = $Scope
        Event = ConvertTo-ToolEnterpriseSafeText $Event 120
        Message = ConvertTo-ToolEnterpriseSafeText $Message 2048
        Data = $Data
    }
    $line = ($record | ConvertTo-Json -Depth 10 -Compress) + [Environment]::NewLine
    $created = $false
    $mutex = New-Object Threading.Mutex($false, "Global\ThanhViet.ToolKiemTra.v4.3.EnterpriseAudit", [ref]$created)
    try {
        if (-not $mutex.WaitOne(5000)) { throw "Không lấy được khóa ghi audit." }
        try { [IO.File]::AppendAllText($path, $line, (New-Object Text.UTF8Encoding($false))) }
        finally { $mutex.ReleaseMutex() }
    } finally { $mutex.Dispose() }
}

function ConvertTo-ToolEnterpriseIPv4UInt32 {
    param([Parameter(Mandatory = $true)][string]$Address)
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        throw "Địa chỉ IPv4 không hợp lệ: $Address"
    }
    $bytes = $parsed.GetAddressBytes()
    $value = ([uint64]$bytes[0] * 16777216) + ([uint64]$bytes[1] * 65536) + ([uint64]$bytes[2] * 256) + [uint64]$bytes[3]
    return [uint32]$value
}

function ConvertFrom-ToolEnterpriseIPv4UInt32 {
    param([Parameter(Mandatory = $true)][uint32]$Value)
    $bytes = New-Object byte[] 4
    $bytes[0] = [byte](([uint64]$Value -shr 24) -band 255)
    $bytes[1] = [byte](([uint64]$Value -shr 16) -band 255)
    $bytes[2] = [byte](([uint64]$Value -shr 8) -band 255)
    $bytes[3] = [byte]([uint64]$Value -band 255)
    return (New-Object Net.IPAddress(,$bytes)).ToString()
}

function Get-ToolEnterpriseCidrInfo {
    param([Parameter(Mandatory = $true)][string]$Cidr)
    if ($Cidr -notmatch '^([^/]+)/(\d{1,2})$') { throw "CIDR không hợp lệ: $Cidr" }
    $address = $matches[1]
    $prefixLength = [int]$matches[2]
    if ($prefixLength -lt 0 -or $prefixLength -gt 32) { throw "Prefix CIDR phải từ 0 đến 32." }
    $ipValue = ConvertTo-ToolEnterpriseIPv4UInt32 -Address $address
    $allBits = [uint64]4294967295
    $mask64 = if ($prefixLength -eq 0) { [uint64]0 } else { (($allBits -shl (32 - $prefixLength)) -band $allBits) }
    $network64 = ([uint64]$ipValue) -band $mask64
    $hostMask64 = ($allBits -bxor $mask64) -band $allBits
    $broadcast64 = $network64 -bor $hostMask64
    $hostCount = if ($prefixLength -ge 31) { [uint64]($broadcast64 - $network64 + 1) } else { [uint64][Math]::Max(0, [double]($broadcast64 - $network64 - 1)) }
    return [pscustomobject][ordered]@{
        Cidr = "$(ConvertFrom-ToolEnterpriseIPv4UInt32 -Value ([uint32]$network64))/$prefixLength"
        PrefixLength = $prefixLength
        NetworkValue = [uint32]$network64
        BroadcastValue = [uint32]$broadcast64
        HostCount = $hostCount
    }
}

function Test-ToolEnterpriseIpInCidr {
    param([Parameter(Mandatory = $true)][string]$Address, [Parameter(Mandatory = $true)][string]$Cidr)
    try {
        $info = Get-ToolEnterpriseCidrInfo -Cidr $Cidr
        $value = ConvertTo-ToolEnterpriseIPv4UInt32 -Address $Address
        return [bool](([uint64]$value -ge [uint64]$info.NetworkValue) -and ([uint64]$value -le [uint64]$info.BroadcastValue))
    } catch { return $false }
}

function Get-ToolEnterpriseCidrAddresses {
    param([Parameter(Mandatory = $true)][string]$Cidr, [int]$MaximumHosts = $script:ToolEnterpriseMaximumScanHosts)
    $info = Get-ToolEnterpriseCidrInfo -Cidr $Cidr
    if ([uint64]$info.HostCount -gt [uint64]$MaximumHosts) {
        throw "Dải $($info.Cidr) có $($info.HostCount) địa chỉ; giới hạn mỗi lần quét là $MaximumHosts. Hãy chia nhỏ dải mạng."
    }
    $start = if ($info.PrefixLength -ge 31) { [uint64]$info.NetworkValue } else { [uint64]$info.NetworkValue + 1 }
    $end = if ($info.PrefixLength -ge 31) { [uint64]$info.BroadcastValue } else { [uint64]$info.BroadcastValue - 1 }
    $addresses = New-Object System.Collections.Generic.List[string]
    for ($value = $start; $value -le $end; $value++) {
        [void]$addresses.Add((ConvertFrom-ToolEnterpriseIPv4UInt32 -Value ([uint32]$value)))
    }
    return $addresses.ToArray()
}

function ConvertTo-ToolEnterprisePrefixLength {
    param([Parameter(Mandatory = $true)][string]$SubnetMask)
    $bytes = ([Net.IPAddress]::Parse($SubnetMask)).GetAddressBytes()
    $bits = ([BitConverter]::ToString($bytes)).Replace("-", "")
    $binary = ""
    foreach ($character in $bits.ToCharArray()) {
        $binary += [Convert]::ToString([Convert]::ToInt32([string]$character, 16), 2).PadLeft(4, '0')
    }
    if ($binary -notmatch '^1*0*$') { throw "Subnet mask không liên tục: $SubnetMask" }
    return ($binary -replace '0', '').Length
}

function Test-ToolEnterprisePrivateIPv4Address {
    param([Parameter(Mandatory = $true)][string]$Address)
    try {
        [void](ConvertTo-ToolEnterpriseIPv4UInt32 -Address $Address)
        $octets = @($Address.Split(".") | ForEach-Object { [int]$_ })
        if ($octets.Count -ne 4) { return $false }
        if ($octets[0] -eq 10) { return $true }
        if ($octets[0] -eq 172 -and $octets[1] -ge 16 -and $octets[1] -le 31) { return $true }
        if ($octets[0] -eq 192 -and $octets[1] -eq 168) { return $true }
        if ($octets[0] -eq 100 -and $octets[1] -ge 64 -and $octets[1] -le 127) { return $true }
    } catch {}
    return $false
}

function Get-ToolEnterpriseLocalIPv4Profiles {
    $profiles = New-Object System.Collections.Generic.List[object]
    foreach ($adapter in @(Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue)) {
        $addresses = @($adapter.IPAddress)
        $masks = @($adapter.IPSubnet)
        $gateways = @($adapter.DefaultIPGateway)
        $hasDefaultGateway = [bool](@($gateways | Where-Object {
            [string]$_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and [string]$_ -ne "0.0.0.0"
        }).Count -gt 0)
        $metric = 999999
        try {
            if ($null -ne $adapter.IPConnectionMetric) { $metric = [int]$adapter.IPConnectionMetric }
        } catch {}
        $interfaceIndex = 999999
        try {
            if ($null -ne $adapter.InterfaceIndex) { $interfaceIndex = [int]$adapter.InterfaceIndex }
        } catch {}

        for ($index = 0; $index -lt $addresses.Count; $index++) {
            $address = [string]$addresses[$index]
            if ($address -notmatch '^\d{1,3}(?:\.\d{1,3}){3}$' -or $address -match '^(0\.|127\.|169\.254\.)') { continue }
            try {
                $addressValue = ConvertTo-ToolEnterpriseIPv4UInt32 -Address $address
                $firstOctet = [int]($address.Split("."))[0]
                if ($firstOctet -ge 224) { continue }
                $mask = if ($index -lt $masks.Count -and [string]$masks[$index] -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
                    [string]$masks[$index]
                } else { "255.255.255.0" }
                $prefix = ConvertTo-ToolEnterprisePrefixLength -SubnetMask $mask
                $info = Get-ToolEnterpriseCidrInfo -Cidr "$address/$prefix"
                [void]$profiles.Add([pscustomobject][ordered]@{
                    Address = $address
                    AddressValue = [uint32]$addressValue
                    PrefixLength = [int]$prefix
                    Cidr = [string]$info.Cidr
                    SubnetMask = $mask
                    HasDefaultGateway = $hasDefaultGateway
                    DefaultGateway = (@($gateways | Where-Object { [string]$_ -match '^\d{1,3}(?:\.\d{1,3}){3}$' }) -join ",")
                    IsPrivate = (Test-ToolEnterprisePrivateIPv4Address -Address $address)
                    Metric = $metric
                    InterfaceIndex = $interfaceIndex
                    AdapterDescription = ConvertTo-ToolEnterpriseSafeText ([string]$adapter.Description) 200
                })
            } catch {}
        }
    }

    $ordered = @($profiles.ToArray() | Sort-Object -Property @{Expression={ if ([bool]$_.HasDefaultGateway) { 0 } else { 1 } }}, @{Expression={ if ([bool]$_.IsPrivate) { 0 } else { 1 } }}, @{Expression={ [int]$_.Metric }}, @{Expression={ [int]$_.InterfaceIndex }}, @{Expression={ [uint32]$_.AddressValue }})
    $result = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($profile in $ordered) {
        $key = [string]$profile.Address
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true
        [void]$result.Add($profile)
    }
    return $result.ToArray()
}

function Get-ToolEnterpriseLocalIPv4Addresses {
    return @((Get-ToolEnterpriseLocalIPv4Profiles) | ForEach-Object { [string]$_.Address })
}

function Get-ToolEnterprisePreferredServerAddress {
    $profiles = @(Get-ToolEnterpriseLocalIPv4Profiles)
    if ($profiles.Count -eq 0) { return "" }
    return [string]$profiles[0].Address
}

function Get-ToolEnterpriseLocalCidrs {
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($profile in @(Get-ToolEnterpriseLocalIPv4Profiles)) {
        $cidr = [string]$profile.Cidr
        if (-not [string]::IsNullOrWhiteSpace($cidr) -and $result -notcontains $cidr) {
            [void]$result.Add($cidr)
        }
    }
    return $result.ToArray()
}

function Get-ToolEnterpriseLocalDiscoveryCidrs {
    param([int]$MaximumHosts = $script:ToolEnterpriseMaximumScanHosts)
    $result = New-Object System.Collections.Generic.List[string]
    foreach ($profile in @(Get-ToolEnterpriseLocalIPv4Profiles)) {
        try {
            $info = Get-ToolEnterpriseCidrInfo -Cidr ([string]$profile.Cidr)
            if ([uint64]$info.HostCount -gt [uint64]$MaximumHosts) {
                # Giới hạn dò tự động ở khối /22 chứa chính card mạng. Dải lớn
                # hơn vẫn có thể được quản trị viên nhập tay để tránh quét ồ ạt.
                $info = Get-ToolEnterpriseCidrInfo -Cidr ("{0}/22" -f [string]$profile.Address)
            }
            if ($result -notcontains [string]$info.Cidr) { [void]$result.Add([string]$info.Cidr) }
        } catch {}
    }
    return $result.ToArray()
}

function Test-ToolEnterpriseHostName {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value.Length -lt 1 -or $Value.Length -gt 253) { return $false }
    if ($Value -match '^\d{1,3}(?:\.\d{1,3}){3}$') {
        $parsed = $null
        return [Net.IPAddress]::TryParse($Value, [ref]$parsed)
    }
    return [bool]($Value -match '^(?=.{1,253}$)(?:[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?\.)*[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?$')
}

function Get-ToolEnterpriseServerConfig {
    $paths = Initialize-ToolEnterpriseStorage
    return (Read-ToolEnterpriseJson -Path $paths.ServerConfig)
}

function New-ToolEnterpriseServerConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ServerName,
        [Parameter(Mandatory = $true)][string]$AdminCode,
        [string]$BindAddress = "0.0.0.0",
        [ValidateRange(1024, 65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [string[]]$AllowedCidrs = @()
    )

    $paths = Initialize-ToolEnterpriseStorage
    if (Test-Path -LiteralPath $paths.ServerConfig -PathType Leaf) { throw "Máy này đã có cấu hình máy chủ. Hãy xác thực mã quản trị để chỉnh sửa." }
    $safeName = ConvertTo-ToolEnterpriseSafeText $ServerName 100
    if ([string]::IsNullOrWhiteSpace($safeName)) { throw "Tên máy chủ không được để trống." }
    if ($BindAddress -ne "0.0.0.0") {
        $parsedAddress = $null
        if (-not [Net.IPAddress]::TryParse($BindAddress, [ref]$parsedAddress) -or $parsedAddress.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
            throw "BindAddress phải là IPv4 hoặc 0.0.0.0."
        }
    }
    $normalizedCidrs = New-Object System.Collections.Generic.List[string]
    foreach ($cidr in @($AllowedCidrs)) {
        if ([string]::IsNullOrWhiteSpace($cidr)) { continue }
        $normalized = (Get-ToolEnterpriseCidrInfo -Cidr $cidr.Trim()).Cidr
        if ($normalizedCidrs -notcontains $normalized) { [void]$normalizedCidrs.Add($normalized) }
    }
    if ($normalizedCidrs.Count -eq 0) {
        foreach ($localCidr in @(Get-ToolEnterpriseLocalCidrs)) { [void]$normalizedCidrs.Add($localCidr) }
    }
    if ($normalizedCidrs.Count -eq 0) {
        throw "Không tự nhận được dải mạng an toàn. Hãy nhập CIDR thủ công (ví dụ 192.168.1.0/24)."
    }
    $masterSecret = New-ToolEnterpriseRandomBytes -Length 32
    $pairingSecret = New-ToolEnterpriseRandomBytes -Length 24
    Set-ToolEnterpriseSecret -Path $paths.ServerMasterSecret -Secret $masterSecret
    Set-ToolEnterpriseSecret -Path $paths.ServerPairingSecret -Secret $pairingSecret
    $fingerprint = ([BitConverter]::ToString((Get-ToolEnterpriseSha256Bytes -Bytes $masterSecret))).Replace("-", "").Substring(0, 24)
    $config = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        Role = "Server"
        ServerId = [Guid]::NewGuid().ToString("N")
        ServerName = $safeName
        BindAddress = $BindAddress
        Port = $Port
        AllowedCidrs = $normalizedCidrs.ToArray()
        AuthorityFingerprint = $fingerprint
        AdminVerifier = New-ToolEnterpriseAdminVerifier -AdminCode $AdminCode
        PairingExpiresAtUtc = [DateTime]::UtcNow.AddHours(24).ToString("o")
        CreatedAtUtc = [DateTime]::UtcNow.ToString("o")
        UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    Write-ToolEnterpriseJson -Path $paths.ServerConfig -Value $config
    Write-ToolEnterpriseAudit -Scope Server -Event "Server.ConfigurationCreated" -Message "Đã tạo cấu hình máy chủ enterprise." -Data ([ordered]@{
        ServerId=$config.ServerId; ServerName=$config.ServerName; Port=$config.Port; AllowedCidrs=$config.AllowedCidrs; AuthorityFingerprint=$config.AuthorityFingerprint
    })
    [Array]::Clear($masterSecret, 0, $masterSecret.Length)
    return $config
}

function Test-ToolEnterpriseServerHostRunning {
    $paths = Initialize-ToolEnterpriseStorage
    $pidRecord = $null
    try { $pidRecord = Read-ToolEnterpriseJson -Path $paths.ServerPid -MaximumBytes 65536 } catch {}
    if (-not $pidRecord -or [int]$pidRecord.ProcessId -le 0) { return $false }

    $process = $null
    try { $process = Get-Process -Id ([int]$pidRecord.ProcessId) -ErrorAction Stop } catch { return $false }
    try {
        $recordedStart = [DateTime]::Parse(
            [string]$pidRecord.StartedAtUtc,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::RoundtripKind
        ).ToUniversalTime()
        $actualStart = $process.StartTime.ToUniversalTime()
        if ([Math]::Abs(($actualStart - $recordedStart).TotalSeconds) -gt 30) {
            return $false
        }
    } catch {
        # Nếu bản ghi cũ thiếu thời gian, PID còn tồn tại vẫn được xem là đang
        # chạy để tránh xóa cấu hình dưới một server chưa dừng hẳn.
    }
    return $true
}

function Assert-ToolEnterpriseDirectoryTreeSafe {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $full = Assert-ToolEnterprisePath -Path $Directory
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return }
    if (Test-ToolEnterpriseReparsePoint -Path $full) {
        throw "Từ chối xóa dữ liệu trong thư mục reparse point: $full"
    }
    foreach ($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop)) {
        [void](Assert-ToolEnterprisePath -Path $item.FullName)
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Từ chối xóa mục reparse point trong vùng enterprise: $($item.FullName)"
        }
        if ($item.PSIsContainer) {
            Assert-ToolEnterpriseDirectoryTreeSafe -Directory $item.FullName
        }
    }
}

function Clear-ToolEnterpriseDirectoryContent {
    param([Parameter(Mandatory = $true)][string]$Directory)

    $full = Assert-ToolEnterprisePath -Path $Directory
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return 0 }
    Assert-ToolEnterpriseDirectoryTreeSafe -Directory $full
    $removedFileCount = 0
    foreach ($item in @(Get-ChildItem -LiteralPath $full -Force -ErrorAction Stop)) {
        if ($item.PSIsContainer) {
            $removedFileCount += [int](Clear-ToolEnterpriseDirectoryContent -Directory $item.FullName)
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
        } else {
            Remove-Item -LiteralPath $item.FullName -Force -ErrorAction Stop
            $removedFileCount++
        }
    }
    return $removedFileCount
}

function Remove-ToolEnterpriseFileSafe {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = Assert-ToolEnterprisePath -Path $Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { return $false }
    if (Test-ToolEnterpriseReparsePoint -Path $full) {
        throw "Từ chối xóa tệp enterprise là reparse point: $full"
    }
    Remove-Item -LiteralPath $full -Force -ErrorAction Stop
    return $true
}

function Remove-ToolEnterpriseServerConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$AdminCode,
        [ValidateRange(1, 30)][int]$StopTimeoutSeconds = 12
    )

    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseServerConfig
    if (-not $config) { throw "Máy này chưa có cấu hình máy chủ để xóa." }
    if (-not (Test-ToolEnterpriseAdminCode -AdminCode $AdminCode -Verifier $config.AdminVerifier)) {
        throw "Mã quản trị máy chủ không đúng."
    }

    Write-ToolEnterpriseAudit -Scope Server -Event "Server.ConfigurationResetRequested" -Message "Quản trị viên đã yêu cầu xóa cấu hình máy chủ; báo cáo, kết quả và audit sẽ được giữ lại." -Data ([ordered]@{
        ServerId=[string]$config.ServerId; ServerName=[string]$config.ServerName; Port=[int]$config.Port
    })

    New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
    $deadline = [DateTime]::UtcNow.AddSeconds($StopTimeoutSeconds)
    while ((Test-ToolEnterpriseServerHostRunning) -and [DateTime]::UtcNow -lt $deadline) {
        Start-Sleep -Milliseconds 200
    }
    if (Test-ToolEnterpriseServerHostRunning) {
        throw "Máy chủ chưa dừng sau $StopTimeoutSeconds giây. Cấu hình chưa bị xóa; hãy dừng máy chủ rồi thử lại."
    }

    # Kiểm tra toàn bộ cây trước khi xóa để không bao giờ đi qua
    # junction/symlink do bên ngoài chèn vào vùng dữ liệu.
    foreach ($directory in @($paths.ServerClients, $paths.ServerClientSecrets, $paths.ServerJobs)) {
        Assert-ToolEnterpriseDirectoryTreeSafe -Directory $directory
    }
    foreach ($file in @(
        $paths.ServerMasterSecret, $paths.ServerPairingSecret, $paths.ServerError,
        $paths.ServerPid, $paths.ServerHeartbeat, $paths.ServerConfig, $paths.ServerStop
    )) {
        $full = Assert-ToolEnterprisePath -Path $file
        if ((Test-Path -LiteralPath $full -PathType Leaf) -and (Test-ToolEnterpriseReparsePoint -Path $full)) {
            throw "Từ chối xóa tệp enterprise là reparse point: $full"
        }
    }

    $removedClientRecords = [int](Clear-ToolEnterpriseDirectoryContent -Directory $paths.ServerClients)
    $removedClientSecrets = [int](Clear-ToolEnterpriseDirectoryContent -Directory $paths.ServerClientSecrets)
    $removedPendingJobs = [int](Clear-ToolEnterpriseDirectoryContent -Directory $paths.ServerJobs)

    foreach ($file in @(
        $paths.ServerMasterSecret, $paths.ServerPairingSecret, $paths.ServerError,
        $paths.ServerPid, $paths.ServerHeartbeat
    )) {
        [void](Remove-ToolEnterpriseFileSafe -Path $file)
    }

    # Xóa server.json gần cuối. Nếu một bước trước đó thất bại, marker stop
    # vẫn còn và mã quản trị vẫn có thể dùng để thử lại an toàn.
    [void](Remove-ToolEnterpriseFileSafe -Path $paths.ServerConfig)
    [void](Remove-ToolEnterpriseFileSafe -Path $paths.ServerStop)

    $auditWritten = $true
    try {
        Write-ToolEnterpriseAudit -Scope Server -Event "Server.ConfigurationResetCompleted" -Message "Đã xóa cấu hình và trạng thái ghép nối máy chủ; giữ nguyên báo cáo, kết quả và audit." -Data ([ordered]@{
            ServerId=[string]$config.ServerId
            ServerName=[string]$config.ServerName
            RemovedClientRecords=$removedClientRecords
            RemovedClientSecrets=$removedClientSecrets
            RemovedPendingJobs=$removedPendingJobs
            PreservedReportsPath=[string]$paths.ServerReports
            PreservedResultsPath=[string]$paths.ServerResults
            PreservedAuditPath=[string]$paths.ServerAudit
        })
    } catch { $auditWritten = $false }

    return [pscustomobject][ordered]@{
        Removed = $true
        ServerId = [string]$config.ServerId
        ServerName = [string]$config.ServerName
        Port = [int]$config.Port
        RemovedClientRecords = $removedClientRecords
        RemovedClientSecrets = $removedClientSecrets
        RemovedPendingJobs = $removedPendingJobs
        PreservedReportsPath = [string]$paths.ServerReports
        PreservedResultsPath = [string]$paths.ServerResults
        PreservedAuditPath = [string]$paths.ServerAudit
        AuditWritten = $auditWritten
    }
}

function Get-ToolEnterprisePairingCode {
    param([Parameter(Mandatory = $true)][string]$AdminCode)
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseServerConfig
    if (-not $config) { throw "Máy chủ chưa được khởi tạo." }
    if (-not (Test-ToolEnterpriseAdminCode -AdminCode $AdminCode -Verifier $config.AdminVerifier)) { throw "Mã quản trị máy chủ không đúng." }
    $expires = [DateTime]::Parse([string]$config.PairingExpiresAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
    if ($expires.ToUniversalTime() -lt [DateTime]::UtcNow) { throw "Mã ghép nối đã hết hạn. Hãy tạo mã mới." }
    $secret = Get-ToolEnterpriseSecret -Path $paths.ServerPairingSecret
    if (-not $secret) { throw "Thiếu secret ghép nối." }
    try { return (ConvertTo-ToolEnterpriseBase64Url -Bytes $secret) }
    finally { [Array]::Clear($secret, 0, $secret.Length) }
}

function Reset-ToolEnterprisePairingCode {
    param([Parameter(Mandatory = $true)][string]$AdminCode, [ValidateRange(1, 168)][int]$ValidHours = 24)
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseServerConfig
    if (-not $config) { throw "Máy chủ chưa được khởi tạo." }
    if (-not (Test-ToolEnterpriseAdminCode -AdminCode $AdminCode -Verifier $config.AdminVerifier)) { throw "Mã quản trị máy chủ không đúng." }
    $secret = New-ToolEnterpriseRandomBytes -Length 24
    Set-ToolEnterpriseSecret -Path $paths.ServerPairingSecret -Secret $secret
    $config.PairingExpiresAtUtc = [DateTime]::UtcNow.AddHours($ValidHours).ToString("o")
    $config.UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-ToolEnterpriseJson -Path $paths.ServerConfig -Value $config
    Write-ToolEnterpriseAudit -Scope Server -Event "Server.PairingCodeRotated" -Message "Đã đổi mã ghép nối; mã cũ hết hiệu lực."
    try { return (ConvertTo-ToolEnterpriseBase64Url -Bytes $secret) }
    finally { [Array]::Clear($secret, 0, $secret.Length) }
}

function Get-ToolEnterpriseClientConfig {
    $paths = Initialize-ToolEnterpriseStorage
    return (Read-ToolEnterpriseJson -Path $paths.ClientConfig)
}

function Set-ToolEnterpriseClientConfiguration {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024, 65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [bool]$AllowRemoteLicenseChanges = $false,
        [bool]$AutoSend = $true
    )

    if (-not (Test-ToolEnterpriseHostName -Value $ServerAddress)) { throw "Địa chỉ máy chủ không hợp lệ." }
    $paths = Initialize-ToolEnterpriseStorage
    $existing = Get-ToolEnterpriseClientConfig
    # Keep the GUID parsing compatible with Windows PowerShell 3/5.1.  An
    # inline cast inside [ref] is rejected by older parsers and can make a
    # workstation fail before it ever reaches the enrollment screen.
    $existingGuid = [Guid]::Empty
    $hasExistingGuid = $false
    if ($existing -and -not [string]::IsNullOrWhiteSpace([string]$existing.ClientId)) {
        $hasExistingGuid = [Guid]::TryParse([string]$existing.ClientId, [ref]$existingGuid)
    }
    $clientId = if ($hasExistingGuid) {
        $existingGuid.ToString("N")
    } else { [Guid]::NewGuid().ToString("N") }
    $config = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        Role = "Client"
        ClientId = $clientId
        ComputerName = [Environment]::MachineName
        ServerAddress = $ServerAddress.Trim()
        Port = $Port
        ServerId = if ($existing) { [string]$existing.ServerId } else { "" }
        Enrolled = [bool]($existing -and $existing.Enrolled -and (Test-Path -LiteralPath $paths.ClientSecret -PathType Leaf))
        AllowRemoteLicenseChanges = [bool]$AllowRemoteLicenseChanges
        AutoSend = [bool]$AutoSend
        EnrolledAtUtc = if ($existing) { [string]$existing.EnrolledAtUtc } else { "" }
        UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
    Write-ToolEnterpriseJson -Path $paths.ClientConfig -Value $config
    return $config
}

function Get-ToolEnterpriseLicenseStatusText {
    param([int]$Status)
    switch ($Status) {
        0 { "Unlicensed" }
        1 { "Licensed" }
        2 { "OOBGrace" }
        3 { "OOTGrace" }
        4 { "NonGenuineGrace" }
        5 { "Notification" }
        6 { "ExtendedGrace" }
        default { "Unknown" }
    }
}

function Get-ToolEnterpriseLicenseChannel {
    param([string]$Description)
    if ($Description -match '(?i)VOLUME_KMSCLIENT') { return "VOLUME_KMSCLIENT" }
    if ($Description -match '(?i)VOLUME_MAK') { return "VOLUME_MAK" }
    if ($Description -match '(?i)OEM') { return "OEM" }
    if ($Description -match '(?i)RETAIL') { return "RETAIL" }
    if ($Description -match '(?i)SUBSCRIPTION') { return "SUBSCRIPTION" }
    return "UNKNOWN"
}

function Get-ToolEnterpriseLicensingProducts {
    $products = @()
    try {
        if (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            $products = @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction Stop)
        } else {
            $products = @(Get-WmiObject -Class SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL" -ErrorAction Stop)
        }
    } catch {
        try { $products = @(Get-WmiObject -Class SoftwareLicensingProduct -ErrorAction Stop | Where-Object PartialProductKey) }
        catch { $products = @() }
    }
    return $products
}

function ConvertTo-ToolEnterpriseLicenseRecord {
    param([Parameter(Mandatory = $true)][object]$Product)
    return [pscustomobject][ordered]@{
        Name = ConvertTo-ToolEnterpriseSafeText $Product.Name 300
        Description = ConvertTo-ToolEnterpriseSafeText $Product.Description 500
        LicenseStatus = [int]$Product.LicenseStatus
        LicenseStatusText = Get-ToolEnterpriseLicenseStatusText -Status ([int]$Product.LicenseStatus)
        Channel = Get-ToolEnterpriseLicenseChannel -Description ([string]$Product.Description)
        PartialProductKey = ConvertTo-ToolEnterpriseSafeText $Product.PartialProductKey 5
        ProductId = ConvertTo-ToolEnterpriseSafeText $Product.ID 80
        ApplicationId = ConvertTo-ToolEnterpriseSafeText $Product.ApplicationID 80
        KmsServer = ConvertTo-ToolEnterpriseSafeText $Product.KeyManagementServiceMachine 255
        GraceMinutes = if ($null -ne $Product.GracePeriodRemaining) { [int64]$Product.GracePeriodRemaining } else { 0 }
    }
}

function Get-ToolEnterpriseLicenseSnapshot {
    param([string]$ClientId = "")

    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        $config = Get-ToolEnterpriseClientConfig
        $ClientId = if ($config) { [string]$config.ClientId } else { [Guid]::NewGuid().ToString("N") }
    }
    $currentVersion = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion" -ErrorAction SilentlyContinue
    $productName = if ($currentVersion.ProductName) { [string]$currentVersion.ProductName } else { "Windows" }
    $build = if ($currentVersion.CurrentBuildNumber) { [string]$currentVersion.CurrentBuildNumber } else { [string][Environment]::OSVersion.Version.Build }
    if ([int64]$build -ge 22000 -and $productName -match "Windows 10") { $productName = $productName -replace "Windows 10", "Windows 11" }
    $allProducts = @(Get-ToolEnterpriseLicensingProducts)
    $windowsLicenses = @($allProducts | Where-Object { $_.Name -match "Windows" } | Sort-Object LicenseStatus -Descending | ForEach-Object { ConvertTo-ToolEnterpriseLicenseRecord $_ })
    $officeLicenses = @($allProducts | Where-Object { $_.Name -match "Office" } | Sort-Object LicenseStatus -Descending | ForEach-Object { ConvertTo-ToolEnterpriseLicenseRecord $_ })
    $networkAddresses = New-Object System.Collections.Generic.List[string]
    foreach ($adapter in @(Get-WmiObject -Class Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" -ErrorAction SilentlyContinue)) {
        foreach ($address in @($adapter.IPAddress)) {
            if ([string]$address -match '^\d{1,3}(?:\.\d{1,3}){3}$' -and $address -notmatch '^(127\.|169\.254\.)') {
                if ($networkAddresses -notcontains [string]$address) { [void]$networkAddresses.Add([string]$address) }
            }
        }
    }
    $officeConfiguration = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    if (-not $officeConfiguration) {
        $officeConfiguration = Get-ItemProperty -LiteralPath "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration" -ErrorAction SilentlyContinue
    }
    $capability = if (Get-Command Get-ToolCapabilityProfile -ErrorAction SilentlyContinue) { Get-ToolCapabilityProfile } else { $null }
    $data = [ordered]@{
        CreatedAt = [DateTime]::UtcNow.ToString("o")
        ClientId = $ClientId
        ComputerName = [Environment]::MachineName
        Domain = ConvertTo-ToolEnterpriseSafeText $env:USERDOMAIN 180
        NetworkAddresses = $networkAddresses.ToArray()
        OperatingSystem = [ordered]@{
            ProductName = $productName
            Edition = ConvertTo-ToolEnterpriseSafeText $currentVersion.EditionID 100
            DisplayVersion = ConvertTo-ToolEnterpriseSafeText $(if ($currentVersion.DisplayVersion) { $currentVersion.DisplayVersion } else { $currentVersion.ReleaseId }) 80
            BuildNumber = $build
            Architecture = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
        }
        CompatibilityTier = if ($capability) { [string]$capability.CompatibilityTier } else { "Unknown" }
        WindowsLicenses = $windowsLicenses
        OfficeLicenses = $officeLicenses
        OfficeInstallation = [ordered]@{
            ProductReleaseIds = ConvertTo-ToolEnterpriseSafeText $officeConfiguration.ProductReleaseIds 400
            Version = ConvertTo-ToolEnterpriseSafeText $officeConfiguration.VersionToReport 80
            Platform = ConvertTo-ToolEnterpriseSafeText $officeConfiguration.Platform 40
        }
        Privacy = [ordered]@{
            FullProductKeyIncluded = $false
            UserNameIncluded = $false
            MacAddressIncluded = $false
        }
    }
    if (Get-Command New-ToolReportEnvelope -ErrorAction SilentlyContinue) {
        return (New-ToolReportEnvelope -ReportKind "EnterpriseInventory" -ToolVersion $script:ToolEnterpriseToolVersion -Data $data)
    }
    return [pscustomobject]$data
}

function Get-ToolEnterpriseBaseUri {
    param([Parameter(Mandatory = $true)][string]$ServerAddress, [ValidateRange(1024,65535)][int]$Port)
    if (-not (Test-ToolEnterpriseHostName -Value $ServerAddress)) { throw "Địa chỉ máy chủ không hợp lệ." }
    return "http://$ServerAddress`:$Port/tool/v1"
}

function Invoke-ToolEnterpriseHttpRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("GET", "POST")][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [AllowNull()][object]$Body = $null,
        [hashtable]$Headers = @{},
        [ValidateRange(500, 30000)][int]$TimeoutMs = 5000
    )

    if ($Uri -notmatch '^http://[A-Za-z0-9.\-]+:\d{2,5}/tool/v1(?:/[A-Za-z0-9\-]+)?$') { throw "URI enterprise không hợp lệ." }
    $request = [Net.HttpWebRequest]::Create($Uri)
    $request.Method = $Method
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    $request.UserAgent = "ThanhViet-Tool-Kiem-Tra/$($script:ToolEnterpriseToolVersion)"
    foreach ($name in $Headers.Keys) { $request.Headers[[string]$name] = [string]$Headers[$name] }
    if ($Method -eq "POST") {
        $json = if ($null -eq $Body) { "{}" } else { $Body | ConvertTo-Json -Depth 14 -Compress }
        $bytes = [Text.Encoding]::UTF8.GetBytes($json)
        if ($bytes.Length -gt $script:ToolEnterpriseMaximumRequestBytes) { throw "Yêu cầu enterprise vượt giới hạn." }
        $request.ContentType = "application/json; charset=utf-8"
        $request.ContentLength = $bytes.Length
        $stream = $request.GetRequestStream()
        try { $stream.Write($bytes, 0, $bytes.Length) } finally { $stream.Dispose() }
    }
    try {
        $response = [Net.HttpWebResponse]$request.GetResponse()
    } catch [Net.WebException] {
        if ($_.Exception.Response) {
            $response = [Net.HttpWebResponse]$_.Exception.Response
        } else { throw }
    }
    try {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $responseText = $reader.ReadToEnd() } finally { $reader.Dispose() }
        if ([int]$response.StatusCode -lt 200 -or [int]$response.StatusCode -ge 300) {
            throw "Máy chủ trả HTTP $([int]$response.StatusCode): $(ConvertTo-ToolEnterpriseSafeText $responseText 500)"
        }
        if ([string]::IsNullOrWhiteSpace($responseText)) { return $null }
        return ($responseText | ConvertFrom-Json)
    } finally { $response.Close() }
}

function Test-ToolEnterpriseServerConnection {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [int]$TimeoutMs = 1200
    )
    try {
        $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress $ServerAddress -Port $Port
        $status = Invoke-ToolEnterpriseHttpRequest -Method GET -Uri "$baseUri/status" -TimeoutMs $TimeoutMs
        if ([string]$status.ProtocolVersion -ne $script:ToolEnterpriseProtocolVersion) { return $null }
        return $status
    } catch { return $null }
}

function Register-ToolEnterpriseClient {
    param(
        [Parameter(Mandatory = $true)][string]$ServerAddress,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [Parameter(Mandatory = $true)][string]$PairingCode,
        [bool]$AllowRemoteLicenseChanges = $false,
        [bool]$AutoSend = $true
    )

    $pairingSecret = ConvertFrom-ToolEnterpriseBase64Url -Text $PairingCode.Trim()
    if ($pairingSecret.Length -lt 20) { throw "Mã ghép nối không hợp lệ." }
    $paths = Initialize-ToolEnterpriseStorage
    $config = Set-ToolEnterpriseClientConfiguration -ServerAddress $ServerAddress -Port $Port -AllowRemoteLicenseChanges:$AllowRemoteLicenseChanges -AutoSend:$AutoSend
    $requestPayload = [ordered]@{
        ClientId = $config.ClientId
        ComputerName = $config.ComputerName
        ToolVersion = $script:ToolEnterpriseToolVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        AllowRemoteLicenseChanges = [bool]$AllowRemoteLicenseChanges
        NetworkAddresses = @((Get-ToolEnterpriseLicenseSnapshot -ClientId $config.ClientId).NetworkAddresses)
    }
    $envelope = New-ToolEnterpriseEnvelope -Secret $pairingSecret -Context "enroll" -Payload $requestPayload
    $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress $ServerAddress -Port $Port
    $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/enroll" -Body $envelope -TimeoutMs 8000
    $opened = Open-ToolEnterpriseEnvelope -Secret $pairingSecret -ExpectedContext "enroll-response:$($config.ClientId)" -Envelope $responseEnvelope -MaximumAgeMinutes 10
    $response = $opened.Payload
    if (-not [bool]$response.Accepted) { throw "Máy chủ từ chối ghép nối: $(ConvertTo-ToolEnterpriseSafeText $response.Message 500)" }
    $clientSecret = ConvertFrom-ToolEnterpriseBase64Url -Text ([string]$response.ClientSecret)
    if ($clientSecret.Length -ne 32) { throw "Secret máy trạm do máy chủ cấp không hợp lệ." }
    Set-ToolEnterpriseSecret -Path $paths.ClientSecret -Secret $clientSecret
    $config.ServerId = [string]$response.ServerId
    $config.Enrolled = $true
    $config.EnrolledAtUtc = [DateTime]::UtcNow.ToString("o")
    $config.UpdatedAtUtc = [DateTime]::UtcNow.ToString("o")
    Write-ToolEnterpriseJson -Path $paths.ClientConfig -Value $config
    Write-ToolEnterpriseAudit -Scope Client -Event "Client.Enrolled" -Message "Máy trạm đã ghép nối với máy chủ." -Data ([ordered]@{
        ClientId=$config.ClientId; ServerId=$config.ServerId; ServerAddress=$config.ServerAddress; Port=$config.Port; RemoteChanges=[bool]$config.AllowRemoteLicenseChanges
    })
    [Array]::Clear($clientSecret, 0, $clientSecret.Length)
    [Array]::Clear($pairingSecret, 0, $pairingSecret.Length)
    return $config
}

function Add-ToolEnterpriseOutboxReport {
    param([Parameter(Mandatory = $true)][object]$Report)
    $paths = Initialize-ToolEnterpriseStorage
    $bytes = [Text.Encoding]::UTF8.GetBytes(($Report | ConvertTo-Json -Depth 14 -Compress))
    $protected = Protect-ToolEnterpriseBytes -Bytes $bytes
    $path = Join-Path $paths.ClientOutbox (([DateTime]::UtcNow.ToString("yyyyMMddHHmmssfff")) + "-" + [Guid]::NewGuid().ToString("N") + ".queue")
    [IO.File]::WriteAllBytes($path, $protected)
    [Array]::Clear($bytes, 0, $bytes.Length)
    return $path
}

function Send-ToolEnterpriseReport {
    param([Parameter(Mandatory = $true)][object]$Report, [switch]$QueueOnFailure)
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseClientConfig
    if (-not $config -or -not [bool]$config.Enrolled) { throw "Máy trạm chưa ghép nối." }
    $clientSecret = Get-ToolEnterpriseSecret -Path $paths.ClientSecret
    if (-not $clientSecret) { throw "Thiếu secret máy trạm." }
    try {
        $context = "report:$([string]$config.ClientId)"
        $envelope = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context $context -Payload $Report
        $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress ([string]$config.ServerAddress) -Port ([int]$config.Port)
        $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/report" -Body $envelope -Headers @{ "X-Tool-ClientId"=[string]$config.ClientId } -TimeoutMs 8000
        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "report-response:$([string]$config.ClientId)" -Envelope $responseEnvelope
        if (-not [bool]$opened.Payload.Accepted) { throw "Máy chủ không chấp nhận báo cáo." }
        return $opened.Payload
    } catch {
        if ($QueueOnFailure) {
            [void](Add-ToolEnterpriseOutboxReport -Report $Report)
            Write-ToolEnterpriseAudit -Scope Client -Event "Report.Queued" -Message $_.Exception.Message
        }
        throw
    } finally { [Array]::Clear($clientSecret, 0, $clientSecret.Length) }
}

function Get-ToolEnterpriseClientJob {
    <#
      Ask the server for the oldest pending job.  The server returns the job
      envelope (already encrypted with the per-client secret) inside a second
      response envelope, so a network observer cannot learn either the
      operation or a product key.
    #>
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseClientConfig
    if (-not $config -or -not [bool]$config.Enrolled) { throw "Máy trạm chưa ghép nối." }
    $clientSecret = Get-ToolEnterpriseSecret -Path $paths.ClientSecret
    if (-not $clientSecret) { throw "Thiếu secret máy trạm." }
    try {
        $clientId = [string]$config.ClientId
        $request = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "poll:$clientId" -Payload ([ordered]@{
            ClientId = $clientId
            ComputerName = [Environment]::MachineName
            ToolVersion = $script:ToolEnterpriseToolVersion
        })
        $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress ([string]$config.ServerAddress) -Port ([int]$config.Port)
        $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/poll" -Body $request -Headers @{ "X-Tool-ClientId"=$clientId } -TimeoutMs 8000
        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "poll-response:$clientId" -Envelope $responseEnvelope
        return $opened.Payload
    } finally { [Array]::Clear($clientSecret, 0, $clientSecret.Length) }
}

function Send-ToolEnterpriseJobResult {
    param([Parameter(Mandatory = $true)][object]$Result)

    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseClientConfig
    if (-not $config -or -not [bool]$config.Enrolled) { throw "Máy trạm chưa ghép nối." }
    $clientSecret = Get-ToolEnterpriseSecret -Path $paths.ClientSecret
    if (-not $clientSecret) { throw "Thiếu secret máy trạm." }
    try {
        $clientId = [string]$config.ClientId
        $request = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "result:$clientId" -Payload $Result
        $baseUri = Get-ToolEnterpriseBaseUri -ServerAddress ([string]$config.ServerAddress) -Port ([int]$config.Port)
        $responseEnvelope = Invoke-ToolEnterpriseHttpRequest -Method POST -Uri "$baseUri/result" -Body $request -Headers @{ "X-Tool-ClientId"=$clientId } -TimeoutMs 8000
        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "result-response:$clientId" -Envelope $responseEnvelope
        if (-not [bool]$opened.Payload.Accepted) { throw "Máy chủ không chấp nhận kết quả tác vụ." }
        return $opened.Payload
    } finally { [Array]::Clear($clientSecret, 0, $clientSecret.Length) }
}

function Flush-ToolEnterpriseOutbox {
    $paths = Initialize-ToolEnterpriseStorage
    $sent = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $paths.ClientOutbox -Filter "*.queue" -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 100)) {
        try {
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint -or $file.Length -gt 2097152) { throw "Tệp hàng đợi không an toàn." }
            $plain = Unprotect-ToolEnterpriseBytes -Bytes ([IO.File]::ReadAllBytes($file.FullName))
            $report = [Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json
            [void](Send-ToolEnterpriseReport -Report $report)
            Remove-Item -LiteralPath $file.FullName -Force
            $sent++
        } catch { break }
        finally { if ($plain) { [Array]::Clear($plain, 0, $plain.Length) } }
    }
    return $sent
}

function Get-ToolEnterpriseServerClientSecretPath {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($ClientId, [ref]$parsed)) { throw "ClientId không hợp lệ." }
    $paths = Initialize-ToolEnterpriseStorage
    return (Join-Path $paths.ServerClientSecrets ($parsed.ToString("N") + ".bin"))
}

function Set-ToolEnterpriseServerClientSecret {
    param([Parameter(Mandatory = $true)][string]$ClientId, [Parameter(Mandatory = $true)][byte[]]$Secret)
    Set-ToolEnterpriseSecret -Path (Get-ToolEnterpriseServerClientSecretPath -ClientId $ClientId) -Secret $Secret
}

function Get-ToolEnterpriseServerClientSecret {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    return (Get-ToolEnterpriseSecret -Path (Get-ToolEnterpriseServerClientSecretPath -ClientId $ClientId))
}

function Get-ToolEnterpriseServerClientRecordPath {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($ClientId, [ref]$parsed)) { throw "ClientId không hợp lệ." }
    $paths = Initialize-ToolEnterpriseStorage
    return (Join-Path $paths.ServerClients ($parsed.ToString("N") + ".json"))
}

function Save-ToolEnterpriseServerReport {
    param(
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][object]$Report,
        [string]$RemoteAddress = ""
    )

    $paths = Initialize-ToolEnterpriseStorage
    if (Get-Command Test-ToolReportEnvelope -ErrorAction SilentlyContinue) {
        $validation = Test-ToolReportEnvelope -Report $Report -ExpectedReportKind "EnterpriseInventory" -ExpectedToolVersion $script:ToolEnterpriseToolVersion
        if (-not $validation.Valid) { throw "Báo cáo enterprise không hợp lệ: $($validation.Errors -join '; ')" }
    }
    if ([string]$Report.ClientId -ne $ClientId) { throw "ClientId trong báo cáo không khớp." }
    $clientDirectory = Join-Path $paths.ServerReports $ClientId
    if (-not (Test-Path -LiteralPath $clientDirectory -PathType Container)) { New-Item -ItemType Directory -Path $clientDirectory -Force | Out-Null }
    $timestampName = [DateTime]::UtcNow.ToString("yyyyMMdd-HHmmssfff")
    $historyPath = Join-Path $clientDirectory ($timestampName + ".json")
    $latestPath = Join-Path $clientDirectory "latest.json"
    Write-ToolEnterpriseJson -Path $historyPath -Value $Report
    Write-ToolEnterpriseJson -Path $latestPath -Value $Report
    [IO.File]::WriteAllText($latestPath + ".sha256", (Get-ToolEnterpriseSha256Hex -Path $latestPath), (New-Object Text.UTF8Encoding($false)))
    $windows = @($Report.WindowsLicenses | Select-Object -First 1)
    $office = @($Report.OfficeLicenses | Select-Object -First 1)
    $existingRecord = Read-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $ClientId)
    $record = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ClientId = $ClientId
        ComputerName = ConvertTo-ToolEnterpriseSafeText $Report.ComputerName 100
        RemoteAddress = ConvertTo-ToolEnterpriseSafeText $RemoteAddress 80
        NetworkAddresses = @($Report.NetworkAddresses)
        LastSeenUtc = [DateTime]::UtcNow.ToString("o")
        FirstSeenUtc = if ($existingRecord) { [string]$existingRecord.FirstSeenUtc } else { [DateTime]::UtcNow.ToString("o") }
        AllowRemoteLicenseChanges = if ($existingRecord) { [bool]$existingRecord.AllowRemoteLicenseChanges } else { $false }
        WindowsStatus = if ($windows.Count -gt 0) { [string]$windows[0].LicenseStatusText } else { "NotDetected" }
        WindowsChannel = if ($windows.Count -gt 0) { [string]$windows[0].Channel } else { "" }
        WindowsLast5 = if ($windows.Count -gt 0) { [string]$windows[0].PartialProductKey } else { "" }
        OfficeStatus = if ($office.Count -gt 0) { [string]$office[0].LicenseStatusText } else { "NotDetected" }
        OfficeChannel = if ($office.Count -gt 0) { [string]$office[0].Channel } else { "" }
        OfficeLast5 = if ($office.Count -gt 0) { [string]$office[0].PartialProductKey } else { "" }
        LatestReportPath = $latestPath
    }
    Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $ClientId) -Value $record
    return $record
}

function Get-ToolEnterpriseServerClients {
    $paths = Initialize-ToolEnterpriseStorage
    $clients = New-Object System.Collections.Generic.List[object]
    foreach ($file in @(Get-ChildItem -LiteralPath $paths.ServerClients -Filter "*.json" -File -ErrorAction SilentlyContinue)) {
        try {
            $record = Read-ToolEnterpriseJson -Path $file.FullName
            if ($record) { [void]$clients.Add($record) }
        } catch {}
    }
    return @($clients.ToArray() | Sort-Object ComputerName, ClientId)
}

function Normalize-ToolEnterpriseProductKey {
    param([Parameter(Mandatory = $true)][string]$ProductKey)
    $clean = ($ProductKey -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
    if ($clean.Length -ne 25) { throw "Product key phải có đúng 25 ký tự." }
    return (($clean -split '(.{5})' | Where-Object { $_ }) -join '-')
}

function New-ToolEnterpriseLicenseJob {
    param(
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateSet("InventoryOnly", "WindowsInstallAndActivate", "OfficeInstallAndActivate")][string]$Operation,
        [string]$ProductKey = "",
        [string]$RequestedBy = ""
    )

    $paths = Initialize-ToolEnterpriseStorage
    $clientRecord = Read-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $ClientId)
    if (-not $clientRecord) { throw "Máy trạm chưa được ghép nối hoặc chưa gửi báo cáo." }
    if ($Operation -ne "InventoryOnly" -and -not [bool]$clientRecord.AllowRemoteLicenseChanges) {
        throw "Máy trạm chưa cho phép thay đổi license từ xa."
    }
    $normalizedKey = ""
    if ($Operation -ne "InventoryOnly") { $normalizedKey = Normalize-ToolEnterpriseProductKey -ProductKey $ProductKey }
    $clientSecret = Get-ToolEnterpriseServerClientSecret -ClientId $ClientId
    if (-not $clientSecret) { throw "Thiếu secret của máy trạm." }
    $jobId = [Guid]::NewGuid().ToString("N")
    $job = [ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        JobId = $jobId
        ClientId = $ClientId
        Operation = $Operation
        ProductKey = $normalizedKey
        ProductKeyLast5 = if ($normalizedKey) { $normalizedKey.Substring($normalizedKey.Length - 5) } else { "" }
        RequestedBy = ConvertTo-ToolEnterpriseSafeText $RequestedBy 180
        RequestedAtUtc = [DateTime]::UtcNow.ToString("o")
        ExpiresAtUtc = [DateTime]::UtcNow.AddHours(24).ToString("o")
    }
    $envelope = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "job:$ClientId`:$jobId" -Payload $job
    $clientJobDirectory = Join-Path $paths.ServerJobs $ClientId
    if (-not (Test-Path -LiteralPath $clientJobDirectory -PathType Container)) { New-Item -ItemType Directory -Path $clientJobDirectory -Force | Out-Null }
    Write-ToolEnterpriseJson -Path (Join-Path $clientJobDirectory ($jobId + ".job")) -Value ([ordered]@{ JobId=$jobId; Envelope=$envelope })
    Write-ToolEnterpriseAudit -Scope Server -Event "Job.Created" -Message "Đã tạo tác vụ $Operation cho máy trạm." -Data ([ordered]@{
        JobId=$jobId; ClientId=$ClientId; Operation=$Operation; ProductKeyLast5=$job.ProductKeyLast5; RequestedBy=$job.RequestedBy
    })
    [Array]::Clear($clientSecret, 0, $clientSecret.Length)
    $normalizedKey = $null
    return [pscustomobject]@{ JobId=$jobId; ClientId=$ClientId; Operation=$Operation; ProductKeyLast5=$job.ProductKeyLast5 }
}

function Get-ToolEnterprisePendingJobPackage {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    $paths = Initialize-ToolEnterpriseStorage
    $directory = Join-Path $paths.ServerJobs $ClientId
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) { return $null }
    $file = Get-ChildItem -LiteralPath $directory -Filter "*.job" -File -ErrorAction SilentlyContinue | Sort-Object CreationTimeUtc | Select-Object -First 1
    if (-not $file) { return $null }
    return (Read-ToolEnterpriseJson -Path $file.FullName)
}

function Save-ToolEnterpriseJobResult {
    param([Parameter(Mandatory = $true)][string]$ClientId, [Parameter(Mandatory = $true)][object]$Result)
    $paths = Initialize-ToolEnterpriseStorage
    $jobId = [string]$Result.JobId
    $parsedJobId = [Guid]::Empty
    if (-not [Guid]::TryParse($jobId, [ref]$parsedJobId)) { throw "JobId kết quả không hợp lệ." }
    $safeResult = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        JobId = $parsedJobId.ToString("N")
        ClientId = $ClientId
        Operation = ConvertTo-ToolEnterpriseSafeText $Result.Operation 80
        Status = ConvertTo-ToolEnterpriseSafeText $Result.Status 60
        ExitCode = [int]$Result.ExitCode
        Message = ConvertTo-ToolEnterpriseSafeText $Result.Message 4000
        ProductKeyLast5 = ConvertTo-ToolEnterpriseSafeText $Result.ProductKeyLast5 5
        StartedAtUtc = ConvertTo-ToolEnterpriseSafeText $Result.StartedAtUtc 60
        CompletedAtUtc = ConvertTo-ToolEnterpriseSafeText $Result.CompletedAtUtc 60
    }
    $resultDirectory = Join-Path $paths.ServerResults $ClientId
    if (-not (Test-Path -LiteralPath $resultDirectory -PathType Container)) { New-Item -ItemType Directory -Path $resultDirectory -Force | Out-Null }
    Write-ToolEnterpriseJson -Path (Join-Path $resultDirectory ($safeResult.JobId + ".json")) -Value $safeResult
    $pendingPath = Join-Path (Join-Path $paths.ServerJobs $ClientId) ($safeResult.JobId + ".job")
    if (Test-Path -LiteralPath $pendingPath -PathType Leaf) { Remove-Item -LiteralPath $pendingPath -Force }
    Write-ToolEnterpriseAudit -Scope Server -Event "Job.Completed" -Message $safeResult.Message -Data ([ordered]@{
        JobId=$safeResult.JobId; ClientId=$ClientId; Operation=$safeResult.Operation; Status=$safeResult.Status; ExitCode=$safeResult.ExitCode; ProductKeyLast5=$safeResult.ProductKeyLast5
    })
    return $safeResult
}

function Invoke-ToolEnterpriseCapturedProcess {
    param([Parameter(Mandatory = $true)][string]$FilePath, [Parameter(Mandatory = $true)][string]$Arguments, [int]$TimeoutSeconds = 120)
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $asyncReaderAvailable = $null -ne ([IO.TextReader].GetMethod("ReadToEndAsync"))
    $psi.RedirectStandardError = $asyncReaderAvailable
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdoutTask = if ($asyncReaderAvailable) { $process.StandardOutput.ReadToEndAsync() } else { $null }
    $stderrTask = if ($asyncReaderAvailable) { $process.StandardError.ReadToEndAsync() } else { $null }
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch {}
        throw "Tiến trình vượt thời gian $TimeoutSeconds giây."
    }
    if ($asyncReaderAvailable) {
        $stdout = $stdoutTask.Result
        $stderr = $stderrTask.Result
    } else {
        # .NET 4.0/PowerShell 3 does not expose the async TextReader API.
        # The official slmgr/OSPP commands emit a small bounded response, so
        # the synchronous fallback is safe on the legacy target.
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = ""
    }
    return [pscustomobject]@{
        ExitCode = [int]$process.ExitCode
        Output = ConvertTo-ToolEnterpriseSafeText (($stdout, $stderr) -join [Environment]::NewLine) 8000
    }
}

function Get-ToolEnterpriseOfficeOsppPaths {
    $result = New-Object System.Collections.Generic.List[string]
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { $_ } | Select-Object -Unique
    $known = @(
        "Microsoft Office\Office16\OSPP.VBS",
        "Microsoft Office\root\Office16\OSPP.VBS",
        "Microsoft Office\Office15\OSPP.VBS"
    )
    foreach ($root in $roots) {
        foreach ($relative in $known) {
            $path = Join-Path $root $relative
            if ((Test-Path -LiteralPath $path -PathType Leaf) -and $result -notcontains $path) { [void]$result.Add($path) }
        }
    }
    if ($result.Count -eq 0) {
        foreach ($root in $roots) {
            $officeRoot = Join-Path $root "Microsoft Office"
            if (-not (Test-Path -LiteralPath $officeRoot -PathType Container)) { continue }
            foreach ($file in @(Get-ChildItem -LiteralPath $officeRoot -Filter "OSPP.VBS" -File -Recurse -ErrorAction SilentlyContinue)) {
                if ($result -notcontains $file.FullName) { [void]$result.Add($file.FullName) }
            }
        }
    }
    return $result.ToArray()
}

function Invoke-ToolEnterpriseLicenseJob {
    param([Parameter(Mandatory = $true)][object]$Job, [bool]$AllowRemoteLicenseChanges)
    $started = [DateTime]::UtcNow
    $operation = [string]$Job.Operation
    $last5 = ConvertTo-ToolEnterpriseSafeText $Job.ProductKeyLast5 5
    $status = "Completed"
    $exitCode = 0
    $message = ""
    $key = [string]$Job.ProductKey
    try {
        $expires = [DateTime]::Parse([string]$Job.ExpiresAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
        if ($expires.ToUniversalTime() -lt [DateTime]::UtcNow) { throw "Tác vụ đã hết hạn." }
        if ($operation -eq "InventoryOnly") {
            $message = "Đã quét lại trạng thái license theo yêu cầu máy chủ."
        } elseif (-not $AllowRemoteLicenseChanges) {
            $status = "Blocked"
            $exitCode = 20
            $message = "Máy trạm chưa bật quyền thay đổi license từ xa."
        } elseif ($operation -eq "WindowsInstallAndActivate") {
            $key = Normalize-ToolEnterpriseProductKey -ProductKey $key
            $service = Get-WmiObject -Class SoftwareLicensingService -ErrorAction Stop | Select-Object -First 1
            if (-not $service) { throw "Không đọc được SoftwareLicensingService." }
            $installResult = $service.InstallProductKey($key)
            if ($null -ne $installResult -and [int64]$installResult -ne 0) { throw "Windows từ chối InstallProductKey, mã $installResult." }
            try { [void]$service.RefreshLicenseStatus() } catch {}
            $cscript = if (Get-Command Get-ToolNativeSystemPath -ErrorAction SilentlyContinue) { Get-ToolNativeSystemPath "cscript.exe" } else { Join-Path $env:SystemRoot "System32\cscript.exe" }
            $slmgr = if (Get-Command Get-ToolNativeSystemPath -ErrorAction SilentlyContinue) { Get-ToolNativeSystemPath "slmgr.vbs" } else { Join-Path $env:SystemRoot "System32\slmgr.vbs" }
            $activation = Invoke-ToolEnterpriseCapturedProcess -FilePath $cscript -Arguments ('//nologo "{0}" /ato' -f $slmgr) -TimeoutSeconds 180
            if ($activation.ExitCode -ne 0 -or $activation.Output -match '(?i)error|0xC[0-9A-F]+') {
                $status = "ActionRequired"
                $exitCode = 23
                $message = "Windows đã tiếp nhận key $last5 nhưng chưa xác nhận kích hoạt: $($activation.Output)"
            } else {
                $message = "Windows đã tiếp nhận key $last5 và hoàn tất yêu cầu kích hoạt."
            }
        } elseif ($operation -eq "OfficeInstallAndActivate") {
            $key = Normalize-ToolEnterpriseProductKey -ProductKey $key
            $osppPaths = @(Get-ToolEnterpriseOfficeOsppPaths)
            if ($osppPaths.Count -eq 0) { throw "Không tìm thấy OSPP.VBS trên máy trạm." }
            $cscript = if (Get-Command Get-ToolNativeSystemPath -ErrorAction SilentlyContinue) { Get-ToolNativeSystemPath "cscript.exe" } else { Join-Path $env:SystemRoot "System32\cscript.exe" }
            $ospp = [string]$osppPaths[0]
            $install = Invoke-ToolEnterpriseCapturedProcess -FilePath $cscript -Arguments ('//nologo "{0}" /inpkey:{1}' -f $ospp, $key) -TimeoutSeconds 180
            if ($install.ExitCode -ne 0 -or $install.Output -match '(?i)error|0xC[0-9A-F]+') { throw "Office từ chối key $last5`: $($install.Output)" }
            $activation = Invoke-ToolEnterpriseCapturedProcess -FilePath $cscript -Arguments ('//nologo "{0}" /act' -f $ospp) -TimeoutSeconds 180
            if ($activation.ExitCode -ne 0 -or $activation.Output -match '(?i)error|0xC[0-9A-F]+') {
                $status = "ActionRequired"
                $exitCode = 23
                $message = "Office đã tiếp nhận key $last5 nhưng chưa xác nhận kích hoạt: $($activation.Output)"
            } else {
                $message = "Office đã tiếp nhận key $last5 và hoàn tất yêu cầu kích hoạt."
            }
        } else { throw "Operation không được hỗ trợ." }
    } catch {
        if ($status -ne "Blocked") {
            $status = "Failed"
            $exitCode = 1
            $message = ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 4000
        }
    } finally { $key = $null }
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        JobId = [string]$Job.JobId
        ClientId = [string]$Job.ClientId
        Operation = $operation
        Status = $status
        ExitCode = $exitCode
        Message = $message
        ProductKeyLast5 = $last5
        StartedAtUtc = $started.ToString("o")
        CompletedAtUtc = [DateTime]::UtcNow.ToString("o")
    }
}

function Export-ToolEnterpriseFleetReport {
    param(
        [Parameter(Mandatory = $true)][string]$DestinationDirectory,
        [switch]$IncludePdf
    )
    if (-not (Get-Command New-ToolProfessionalHtmlDocument -ErrorAction SilentlyContinue)) {
        $reportExportHelper = Join-Path $PSScriptRoot "Tool-ReportExport.ps1"
        if (-not (Test-Path -LiteralPath $reportExportHelper -PathType Leaf)) { throw "Thiếu Tool-ReportExport.ps1." }
        . $reportExportHelper
    }
    $fullDestination = [IO.Path]::GetFullPath($DestinationDirectory)
    if (-not (Test-Path -LiteralPath $fullDestination -PathType Container)) { New-Item -ItemType Directory -Path $fullDestination -Force | Out-Null }
    $clients = @(Get-ToolEnterpriseServerClients)
    $stamp = [DateTime]::Now.ToString("yyyyMMdd-HHmmss")
    $baseName = "bao-cao-quan-ly-license-doanh-nghiep-$stamp"
    $jsonPath = Join-Path $fullDestination ($baseName + ".json")
    $csvPath = Join-Path $fullDestination ($baseName + ".csv")
    $htmlPath = Join-Path $fullDestination ($baseName + ".html")
    $pdfPath = Join-Path $fullDestination ($baseName + ".pdf")
    $manifestPath = Join-Path $fullDestination ($baseName + "-SHA256SUMS.txt")
    $fleet = [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        CreatedAtUtc = [DateTime]::UtcNow.ToString("o")
        ClientCount = $clients.Count
        Clients = $clients
    }
    # Fleet exports are intentionally allowed outside the protected
    # ProgramData store (for example to a file share or the administrator's
    # desktop).  Write them directly after resolving the destination; the
    # internal state files continue to use Write-ToolEnterpriseJson.
    if (Test-ToolEnterpriseReparsePoint -Path $fullDestination) {
        throw "Không thể xuất báo cáo vào thư mục reparse point: $fullDestination"
    }
    [IO.File]::WriteAllText($jsonPath, ($fleet | ConvertTo-Json -Depth 12), (New-Object Text.UTF8Encoding($false)))
    $clients | Select-Object ComputerName,RemoteAddress,LastSeenUtc,WindowsStatus,WindowsChannel,WindowsLast5,OfficeStatus,OfficeChannel,OfficeLast5,AllowRemoteLicenseChanges |
        Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8
    $fleetRows = @($clients | ForEach-Object {
        [pscustomobject][ordered]@{
            "Máy" = [string]$_.ComputerName
            "IP" = [string]$_.RemoteAddress
            "Lần cuối" = [string]$_.LastSeenUtc
            "Windows" = [string]$_.WindowsStatus
            "Kênh Windows" = [string]$_.WindowsChannel
            "Windows Last5" = [string]$_.WindowsLast5
            "Office" = [string]$_.OfficeStatus
            "Kênh Office" = [string]$_.OfficeChannel
            "Office Last5" = [string]$_.OfficeLast5
        }
    })
    $createdAt = [DateTime]::Now
    $activeWindows = @($clients | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.WindowsStatus) -and [string]$_.WindowsStatus -notin @("NotReported","Unknown") }).Count
    $activeOffice = @($clients | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.OfficeStatus) -and [string]$_.OfficeStatus -notin @("NotReported","Unknown") }).Count
    $html = New-ToolProfessionalHtmlDocument `
        -Title "Báo cáo quản lý license doanh nghiệp" `
        -Subtitle "Tổng hợp trạng thái Windows và Office của các máy trạm đã ghép nối; không lưu product key đầy đủ." `
        -Eyebrow "Báo cáo kiểm kê và bảo đảm bản quyền" `
        -Metadata @(
            [pscustomobject]@{Label="Máy chủ";Value=[string]$env:COMPUTERNAME},
            [pscustomobject]@{Label="Thời điểm";Value=$createdAt.ToString("yyyy-MM-dd HH:mm:ss")},
            [pscustomobject]@{Label="Phạm vi";Value="Đội máy doanh nghiệp"},
            [pscustomobject]@{Label="Riêng tư";Value="Chỉ lưu định danh key rút gọn Last5"}
        ) `
        -Cards @(
            [pscustomobject]@{Label="Máy trạm";Value=[string]$clients.Count;Tone="info"},
            [pscustomobject]@{Label="Có trạng thái Windows";Value=[string]$activeWindows;Tone=$(if ($activeWindows -eq $clients.Count) {"ok"} else {"warning"})},
            [pscustomobject]@{Label="Có trạng thái Office";Value=[string]$activeOffice;Tone=$(if ($activeOffice -eq $clients.Count) {"ok"} else {"warning"})},
            [pscustomobject]@{Label="Định dạng";Value="HTML / PDF / JSON / CSV";Tone="info"}
        ) `
        -Sections @(
            [pscustomobject]@{
                Title="Danh sách máy trạm và trạng thái giấy phép"
                BodyHtml=(ConvertTo-ToolHtmlTable -Rows $fleetRows -Columns @("Máy","IP","Lần cuối","Windows","Kênh Windows","Windows Last5","Office","Kênh Office","Office Last5"))
            },
            [pscustomobject]@{
                Title="Giới hạn sử dụng"
                BodyHtml="<p class='note'>Báo cáo là bằng chứng kỹ thuật cục bộ, không thay thế hóa đơn, hợp đồng, tài khoản cấp phép hoặc hồ sơ pháp lý.</p>"
            }
        ) `
        -Footer "Phát triển bởi Thanh Việt · Tool v$($script:ToolEnterpriseToolVersion)" -Culture "vi-VN" -OfflineMode $true
    [IO.File]::WriteAllText($htmlPath, $html, (New-Object Text.UTF8Encoding($false)))
    if (-not (Test-ToolHtmlOfflineSafe -HtmlPath $htmlPath)) { throw "Báo cáo doanh nghiệp không đạt kiểm tra HTML ngoại tuyến." }
    $pdfResult = [pscustomobject][ordered]@{ Success=$false; Engine=""; Path=""; Error="Không yêu cầu xuất PDF." }
    if ($IncludePdf) { $pdfResult = Convert-ToolHtmlToPdf -HtmlPath $htmlPath -PdfPath $pdfPath }
    $manifestLines = @("# SHA-256 báo cáo quản lý license doanh nghiệp Tool v4.3.")
    foreach ($path in @($jsonPath,$csvPath,$htmlPath,$pdfPath)) {
        if (Test-Path -LiteralPath $path -PathType Leaf) { $manifestLines += "$(Get-ToolEnterpriseSha256Hex -Path $path)  $([IO.Path]::GetFileName($path))" }
    }
    [IO.File]::WriteAllLines($manifestPath, $manifestLines, (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{
        JsonPath=$jsonPath
        CsvPath=$csvPath
        HtmlPath=$htmlPath
        PdfPath=if ($pdfResult.Success) { $pdfPath } else { "" }
        Pdf=$pdfResult
        ManifestPath=$manifestPath
        ClientCount=$clients.Count
    }
}

function Find-ToolEnterpriseNetworkDevices {
    param(
        [Parameter(Mandatory = $true)][string]$Cidr,
        [ValidateRange(50, 3000)][int]$TimeoutMs = 350,
        [ValidateRange(1, 128)][int]$ThrottleLimit = 48
    )

    $addresses = @(Get-ToolEnterpriseCidrAddresses -Cidr $Cidr)
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
    $pool.Open()
    $workers = New-Object System.Collections.Generic.List[object]
    $scriptText = @'
param($Address,$TimeoutMs)
$reachable = $false
$latency = -1
$hostName = ""
$ping = New-Object Net.NetworkInformation.Ping
try {
    $reply = $ping.Send($Address, $TimeoutMs)
    if ($reply -and $reply.Status -eq [Net.NetworkInformation.IPStatus]::Success) {
        $reachable = $true
        $latency = [long]$reply.RoundtripTime
        try { $hostName = [Net.Dns]::GetHostEntry($Address).HostName } catch {}
    }
} catch {} finally { $ping.Dispose() }
[pscustomobject]@{ Address=$Address; Reachable=$reachable; LatencyMs=$latency; HostName=$hostName }
'@
    try {
        foreach ($address in $addresses) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($scriptText).AddArgument($address).AddArgument($TimeoutMs)
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($worker in $workers) {
            try {
                foreach ($item in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if ($item.Reachable) { [void]$results.Add($item) }
                }
            } finally { $worker.PowerShell.Dispose() }
        }
        return @($results.ToArray() | Sort-Object { ConvertTo-ToolEnterpriseIPv4UInt32 -Address $_.Address })
    } finally { $pool.Close(); $pool.Dispose() }
}

function Find-ToolEnterpriseServers {
    param(
        [Parameter(Mandatory = $true)][string]$Cidr,
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [ValidateRange(100,3000)][int]$TimeoutMs = 450,
        [ValidateRange(1,128)][int]$ThrottleLimit = 64
    )

    $addresses = @(Get-ToolEnterpriseCidrAddresses -Cidr $Cidr)
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $ThrottleLimit)
    $pool.Open()
    $workers = New-Object System.Collections.Generic.List[object]
    $scriptText = @'
param($Address,$Port,$TimeoutMs)
$response = $null
try {
    $uri = "http://$Address`:$Port/tool/v1/status"
    $request = [Net.HttpWebRequest]::Create($uri)
    $request.Method = "GET"
    $request.Timeout = $TimeoutMs
    $request.ReadWriteTimeout = $TimeoutMs
    $request.AllowAutoRedirect = $false
    $request.Proxy = $null
    $response = [Net.HttpWebResponse]$request.GetResponse()
    if ([int]$response.StatusCode -eq 200) {
        $reader = New-Object IO.StreamReader($response.GetResponseStream(), [Text.Encoding]::UTF8)
        try { $status = $reader.ReadToEnd() | ConvertFrom-Json } finally { $reader.Dispose() }
        if ([string]$status.Service -eq "ThanhViet.ToolKiemTra.EnterpriseServer") {
            [pscustomobject]@{
                Address=$Address
                Port=$Port
                ServerId=[string]$status.ServerId
                ServerName=[string]$status.ServerName
                ToolVersion=[string]$status.ToolVersion
                ProtocolVersion=[string]$status.ProtocolVersion
            }
        }
    }
} catch {} finally { if ($response) { $response.Close() } }
'@
    try {
        foreach ($address in $addresses) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($scriptText).AddArgument($address).AddArgument($Port).AddArgument($TimeoutMs)
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $results = New-Object System.Collections.Generic.List[object]
        foreach ($worker in $workers) {
            try {
                foreach ($item in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if ($item) { [void]$results.Add($item) }
                }
            } finally { $worker.PowerShell.Dispose() }
        }
        return @($results.ToArray() | Sort-Object { ConvertTo-ToolEnterpriseIPv4UInt32 -Address $_.Address })
    } finally { $pool.Close(); $pool.Dispose() }
}

function Find-ToolEnterpriseLocalServers {
    param(
        [ValidateRange(1024,65535)][int]$Port = $script:ToolEnterpriseDefaultPort,
        [ValidateRange(100,3000)][int]$TimeoutMs = 450,
        [ValidateRange(1,128)][int]$ThrottleLimit = 64
    )

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    foreach ($cidr in @(Get-ToolEnterpriseLocalDiscoveryCidrs)) {
        foreach ($server in @(Find-ToolEnterpriseServers -Cidr $cidr -Port $Port -TimeoutMs $TimeoutMs -ThrottleLimit $ThrottleLimit)) {
            $key = if (-not [string]::IsNullOrWhiteSpace([string]$server.ServerId)) {
                [string]$server.ServerId
            } else { "{0}:{1}" -f [string]$server.Address, [int]$server.Port }
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            [void]$results.Add($server)
        }
    }
    return @($results.ToArray() | Sort-Object -Property @{Expression={ ConvertTo-ToolEnterpriseIPv4UInt32 -Address ([string]$_.Address) }})
}

function Get-ToolEnterpriseMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        DefaultPort = $script:ToolEnterpriseDefaultPort
        MaximumRequestBytes = $script:ToolEnterpriseMaximumRequestBytes
        MaximumScanHosts = $script:ToolEnterpriseMaximumScanHosts
        Encryption = "AES-256-CBC + HMAC-SHA256; DPAPI LocalMachine at rest"
        FullProductKeysInReports = $false
        RemoteLicenseChangesRequireClientOptIn = $true
    }
}
