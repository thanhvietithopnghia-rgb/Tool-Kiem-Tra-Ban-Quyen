[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ExePath,
    [Parameter(Mandatory = $true)][string]$SourceDirectory,
    [Parameter(Mandatory = $true)][string]$PayloadList,
    [Parameter(Mandatory = $true)][ValidateSet("x64", "x86")][string]$ExpectedArchitecture
)

$ErrorActionPreference = "Stop"

function Get-Sha256HexFromFile([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace("-", "") }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-Sha256HexFromStream([IO.Stream]$Stream) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Stream))).Replace("-", "") }
    finally { $sha.Dispose() }
}

try {
    $actualArchitecture = if ([Environment]::Is64BitProcess) { "x64" } else { "x86" }
    if ($actualArchitecture -ne $ExpectedArchitecture) {
        throw "Trình kiểm tra đang chạy $actualArchitecture, cần $ExpectedArchitecture."
    }

    $payloadFiles = @($PayloadList -split '\|' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($payloadFiles.Count -eq 0) { throw "Danh sách payload trống." }
    foreach ($name in $payloadFiles) {
        if ([IO.Path]::GetFileName($name) -ne $name) { throw "Tên payload không an toàn: $name" }
    }

    $assembly = [Reflection.Assembly]::LoadFile([IO.Path]::GetFullPath($ExePath))
    $launcherType = $assembly.GetType("ThanhViet.ToolKiemTra.Program", $true)
    $bindingFlags = [Reflection.BindingFlags]::NonPublic -bor [Reflection.BindingFlags]::Static
    $payloadField = $launcherType.GetField("PayloadFiles", $bindingFlags)
    $integrityField = $launcherType.GetField("RequiredIntegrityFiles", $bindingFlags)
    if (-not $payloadField -or -not $integrityField) {
        throw "Không đọc được danh sách payload/toàn vẹn nội bộ của launcher."
    }

    $launcherPayloadFiles = @($payloadField.GetValue($null))
    if ($launcherPayloadFiles.Count -ne $payloadFiles.Count) {
        throw "Danh sách payload nội bộ lệch số lượng so với build: $($launcherPayloadFiles.Count)/$($payloadFiles.Count)."
    }
    for ($index = 0; $index -lt $payloadFiles.Count; $index++) {
        if ([string]$launcherPayloadFiles[$index] -cne [string]$payloadFiles[$index]) {
            throw "Ánh xạ payload nội bộ lệch tại vị trí $index`: $($launcherPayloadFiles[$index]) / $($payloadFiles[$index])."
        }
    }

    $integrityManifestPath = Join-Path $SourceDirectory "TOOL-SHA256SUMS.txt"
    if (-not (Test-Path -LiteralPath $integrityManifestPath -PathType Leaf)) {
        throw "Thiếu TOOL-SHA256SUMS.txt để đối chiếu danh sách toàn vẹn nội bộ."
    }
    $manifestIntegrityFiles = New-Object System.Collections.Generic.List[string]
    foreach ($rawLine in [IO.File]::ReadAllLines($integrityManifestPath)) {
        $line = ([string]$rawLine).Trim()
        if ($line.Length -eq 0 -or $line.StartsWith("#")) { continue }
        $match = [regex]::Match($line, "^[0-9A-Fa-f]{64}[ `t]+\*?(.+)$")
        if (-not $match.Success) {
            throw "TOOL-SHA256SUMS.txt có dòng không hợp lệ khi kiểm tra launcher."
        }
        [void]$manifestIntegrityFiles.Add($match.Groups[1].Value.Trim())
    }

    $launcherIntegrityFiles = @($integrityField.GetValue($null))
    if ($launcherIntegrityFiles.Count -ne $manifestIntegrityFiles.Count) {
        throw "Danh sách toàn vẹn nội bộ lệch số lượng so với manifest: $($launcherIntegrityFiles.Count)/$($manifestIntegrityFiles.Count)."
    }
    for ($index = 0; $index -lt $manifestIntegrityFiles.Count; $index++) {
        if ([string]$launcherIntegrityFiles[$index] -cne [string]$manifestIntegrityFiles[$index]) {
            throw "Danh sách toàn vẹn nội bộ lệch tại vị trí $index`: $($launcherIntegrityFiles[$index]) / $($manifestIntegrityFiles[$index])."
        }
    }

    $resourceNames = @($assembly.GetManifestResourceNames())
    if ($resourceNames.Count -ne $payloadFiles.Count) {
        throw "Số tài nguyên nhúng không khớp: $($resourceNames.Count)/$($payloadFiles.Count)."
    }

    for ($index = 0; $index -lt $payloadFiles.Count; $index++) {
        $resourceName = "payload.$index"
        if ($resourceNames -notcontains $resourceName) { throw "EXE thiếu $resourceName ($($payloadFiles[$index]))." }
        $stream = $assembly.GetManifestResourceStream($resourceName)
        if (-not $stream) { throw "Không đọc được $resourceName." }
        try { $embeddedHash = Get-Sha256HexFromStream $stream }
        finally { $stream.Dispose() }
        $sourcePath = Join-Path $SourceDirectory $payloadFiles[$index]
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { throw "Thiếu payload nguồn: $($payloadFiles[$index])" }
        if ($embeddedHash -ne (Get-Sha256HexFromFile $sourcePath)) {
            throw "Payload nhúng không khớp: $($payloadFiles[$index])"
        }
    }

    Write-Host "EMBEDDED-PAYLOAD $ExpectedArchitecture`: ĐẠT ($($payloadFiles.Count)/$($payloadFiles.Count))" -ForegroundColor Green
    exit 0
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
