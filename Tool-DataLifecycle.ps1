$script:ToolDataStateSchemaVersion = "1.0"
$script:ToolDataSchemaVersion = "2.0"
$script:ToolDataStorageGeneration = "v4.6"
$script:ToolDataLegacyStorageGeneration = "v4.4"
$script:ToolDataToolVersion = "4.8.0.1"
$script:ToolDataMigrationMutexName = "Global\ThanhViet.ToolKiemTra.DataMigration.v4.6"
$script:ToolDataInitializedRoot = ""
$script:ToolDataLifecycleState = $null

function Get-ToolDataRoot {
    $configured = [string]$env:TOOL_DATA_ROOT
    if (-not [string]::IsNullOrWhiteSpace($configured)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($configured))
    }
    $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([string]::IsNullOrWhiteSpace($commonData)) { throw "Không xác định được ProgramData." }
    return (Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\$($script:ToolDataStorageGeneration)")
}

function Get-ToolLegacyDataRoot {
    $configured = [string]$env:TOOL_LEGACY_DATA_ROOT
    if (-not [string]::IsNullOrWhiteSpace($configured)) {
        return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($configured))
    }
    $commonData = [Environment]::GetFolderPath([Environment+SpecialFolder]::CommonApplicationData)
    if ([string]::IsNullOrWhiteSpace($commonData)) { throw "Không xác định được ProgramData." }
    return (Join-Path $commonData "ThanhViet-Tool-Kiem-Tra\$($script:ToolDataLegacyStorageGeneration)")
}

function Test-ToolDataReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $false }
    return [bool]((Get-Item -LiteralPath $Path -Force -ErrorAction Stop).Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Assert-ToolDataPathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $pathFull = [IO.Path]::GetFullPath($Path)
    if (-not $pathFull.StartsWith($rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Đường dẫn dữ liệu nằm ngoài vùng được phép: $pathFull"
    }
    return $pathFull
}

function New-ToolDataDirectorySafe {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Vùng dữ liệu không an toàn: $Path"
        }
        return
    }
    New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
    if (Test-ToolDataReparsePoint -Path $Path) { throw "Vùng dữ liệu là reparse point: $Path" }
}

function Copy-ToolDataTreeNoOverwrite {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [ValidateRange(1, 50000)][int]$MaximumItems = 20000,
        [ValidateRange(1, 2048)][int]$MaximumTotalMegabytes = 512
    )
    if (-not (Test-Path -LiteralPath $Source)) { return [pscustomobject]@{ CopiedFiles=0; CopiedBytes=0L } }
    $sourceItem = Get-Item -LiteralPath $Source -Force -ErrorAction Stop
    if ($sourceItem.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Từ chối migrate reparse point: $Source" }
    $destinationRoot = Get-ToolDataRoot
    [void](Assert-ToolDataPathWithinRoot -Path $Destination -Root $destinationRoot)

    if (-not $sourceItem.PSIsContainer) {
        if ($sourceItem.Length -gt ($MaximumTotalMegabytes * 1MB)) { throw "Tệp migrate vượt giới hạn: $Source" }
        $parent = Split-Path -Parent $Destination
        New-ToolDataDirectorySafe -Path $parent
        if (-not (Test-Path -LiteralPath $Destination)) { Copy-Item -LiteralPath $Source -Destination $Destination -ErrorAction Stop }
        return [pscustomobject]@{ CopiedFiles=$(if (Test-Path -LiteralPath $Destination) { 1 } else { 0 }); CopiedBytes=[int64]$sourceItem.Length }
    }

    New-ToolDataDirectorySafe -Path $Destination
    $entries = @(Get-ChildItem -LiteralPath $Source -Force -Recurse -ErrorAction Stop)
    if ($entries.Count -gt $MaximumItems) { throw "Dữ liệu migrate vượt giới hạn số mục: $($entries.Count)" }
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw "Từ chối migrate cây dữ liệu chứa reparse point: $Source"
    }
    [int64]$totalBytes = [int64](($entries | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum)
    if ($totalBytes -gt ($MaximumTotalMegabytes * 1MB)) { throw "Dữ liệu migrate vượt giới hạn dung lượng: $Source" }

    $sourceRoot = [IO.Path]::GetFullPath($Source).TrimEnd('\')
    foreach ($entry in @($entries | Sort-Object { $_.FullName.Length })) {
        $relative = $entry.FullName.Substring($sourceRoot.Length).TrimStart('\')
        if ([string]::IsNullOrWhiteSpace($relative)) { continue }
        $target = Join-Path $Destination $relative
        [void](Assert-ToolDataPathWithinRoot -Path $target -Root $destinationRoot)
        if ($entry.PSIsContainer) {
            New-ToolDataDirectorySafe -Path $target
        } else {
            New-ToolDataDirectorySafe -Path (Split-Path -Parent $target)
            if (-not (Test-Path -LiteralPath $target)) { Copy-Item -LiteralPath $entry.FullName -Destination $target -ErrorAction Stop }
        }
    }
    return [pscustomobject]@{ CopiedFiles=@($entries | Where-Object { -not $_.PSIsContainer }).Count; CopiedBytes=$totalBytes }
}

function Get-ToolDataFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $stream = [IO.File]::OpenRead($Path)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '') }
        finally { $sha.Dispose() }
    } finally { $stream.Dispose() }
}

function Get-ToolDataTreeManifest {
    param([Parameter(Mandatory = $true)][string]$Path)
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Từ chối kiểm tra reparse point: $Path" }
    if (-not $item.PSIsContainer) {
        return ,([pscustomobject][ordered]@{
            RelativePath=''; Length=[int64]$item.Length; Sha256=(Get-ToolDataFileSha256 -Path $item.FullName)
        })
    }

    $root = [IO.Path]::GetFullPath($item.FullName).TrimEnd('\')
    $files = @(Get-ChildItem -LiteralPath $root -File -Force -Recurse -ErrorAction Stop)
    if (@($files | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw "Từ chối kiểm tra cây dữ liệu chứa reparse point: $Path"
    }
    return @($files | ForEach-Object {
        [pscustomobject][ordered]@{
            RelativePath=$_.FullName.Substring($root.Length).TrimStart('\')
            Length=[int64]$_.Length
            Sha256=(Get-ToolDataFileSha256 -Path $_.FullName)
        }
    } | Sort-Object RelativePath)
}

function Assert-ToolDataMigrationCopy {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $sourceManifest = @(Get-ToolDataTreeManifest -Path $Source)
    $destinationManifest = @(Get-ToolDataTreeManifest -Path $Destination)
    if ($sourceManifest.Count -ne $destinationManifest.Count) {
        throw "Xác minh migration sai số lượng tệp: $Source"
    }
    for ($index = 0; $index -lt $sourceManifest.Count; $index++) {
        $sourceEntry = $sourceManifest[$index]
        $destinationEntry = $destinationManifest[$index]
        if (-not [string]::Equals([string]$sourceEntry.RelativePath, [string]$destinationEntry.RelativePath, [StringComparison]::OrdinalIgnoreCase) -or
            [int64]$sourceEntry.Length -ne [int64]$destinationEntry.Length -or
            -not [string]::Equals([string]$sourceEntry.Sha256, [string]$destinationEntry.Sha256, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Xác minh migration không khớp: $([string]$sourceEntry.RelativePath)"
        }
    }
}

function Merge-ToolDataMigrationStaging {
    param(
        [Parameter(Mandatory = $true)][string]$StagingRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )
    $stagingFull = [IO.Path]::GetFullPath($StagingRoot).TrimEnd('\')
    $destinationFull = [IO.Path]::GetFullPath($DestinationRoot).TrimEnd('\')
    [void](Assert-ToolDataPathWithinRoot -Path $stagingFull -Root $destinationFull)
    $entries = @(Get-ChildItem -LiteralPath $stagingFull -Force -Recurse -ErrorAction Stop |
        Where-Object { $_.FullName -notlike ((Join-Path $stagingFull '.rollback') + '*') } |
        Sort-Object { $_.FullName.Length })
    if (@($entries | Where-Object { $_.Attributes -band [IO.FileAttributes]::ReparsePoint }).Count -gt 0) {
        throw "Từ chối commit migration chứa reparse point."
    }

    $createdFiles = New-Object System.Collections.Generic.List[string]
    $createdDirectories = New-Object System.Collections.Generic.List[string]
    $overwrittenFiles = New-Object System.Collections.Generic.List[object]
    $skippedFiles = New-Object System.Collections.Generic.List[string]
    $rollbackRoot = Join-Path $stagingFull '.rollback'
    try {
        foreach ($entry in $entries) {
            $relative = $entry.FullName.Substring($stagingFull.Length).TrimStart('\')
            if ([string]::IsNullOrWhiteSpace($relative)) { continue }
            $target = Join-Path $destinationFull $relative
            [void](Assert-ToolDataPathWithinRoot -Path $target -Root $destinationFull)
            if ($entry.PSIsContainer) {
                if (Test-Path -LiteralPath $target) {
                    if (-not (Test-Path -LiteralPath $target -PathType Container) -or (Test-ToolDataReparsePoint -Path $target)) {
                        throw "Đích migration không phải thư mục an toàn: $target"
                    }
                } else {
                    New-ToolDataDirectorySafe -Path $target
                    $createdDirectories.Add($target)
                }
                continue
            }

            $overwriteLegacyConfiguration = [string]::Equals($relative, 'approved-kms-servers.txt', [StringComparison]::OrdinalIgnoreCase)
            if (Test-Path -LiteralPath $target) {
                if (-not (Test-Path -LiteralPath $target -PathType Leaf) -or (Test-ToolDataReparsePoint -Path $target)) {
                    throw "Đích migration không phải tệp an toàn: $target"
                }
                if (-not $overwriteLegacyConfiguration) {
                    $skippedFiles.Add($relative)
                    continue
                }
                New-ToolDataDirectorySafe -Path $rollbackRoot
                $backupPath = Join-Path $rollbackRoot ([Guid]::NewGuid().ToString('N') + '.bak')
                Copy-Item -LiteralPath $target -Destination $backupPath -ErrorAction Stop
                $overwrittenFiles.Add([pscustomobject]@{ Target=$target; Backup=$backupPath })
                Copy-Item -LiteralPath $entry.FullName -Destination $target -Force -ErrorAction Stop
            } else {
                New-ToolDataDirectorySafe -Path (Split-Path -Parent $target)
                Copy-Item -LiteralPath $entry.FullName -Destination $target -ErrorAction Stop
                $createdFiles.Add($target)
            }
            if ((Get-ToolDataFileSha256 -Path $entry.FullName) -ne (Get-ToolDataFileSha256 -Path $target)) {
                throw "SHA-256 sau commit migration không khớp: $relative"
            }
        }
    } catch {
        $originalError = [string]$_.Exception.Message
        for ($index = $overwrittenFiles.Count - 1; $index -ge 0; $index--) {
            $record = $overwrittenFiles[$index]
            try { Copy-Item -LiteralPath $record.Backup -Destination $record.Target -Force -ErrorAction Stop } catch {}
        }
        for ($index = $createdFiles.Count - 1; $index -ge 0; $index--) {
            $createdFile = $createdFiles[$index]
            try { if (Test-Path -LiteralPath $createdFile -PathType Leaf) { Remove-Item -LiteralPath $createdFile -Force -ErrorAction Stop } } catch {}
        }
        foreach ($createdDirectory in @($createdDirectories.ToArray()) | Sort-Object Length -Descending) {
            try {
                if ((Test-Path -LiteralPath $createdDirectory -PathType Container) -and
                    @(Get-ChildItem -LiteralPath $createdDirectory -Force -ErrorAction Stop).Count -eq 0) {
                    Remove-Item -LiteralPath $createdDirectory -Force -ErrorAction Stop
                }
            } catch {}
        }
        throw "Migration đã được hoàn tác sau lỗi: $originalError"
    }
    return [pscustomobject][ordered]@{
        CreatedFileCount=[int]$createdFiles.Count
        CreatedDirectoryCount=[int]$createdDirectories.Count
        OverwrittenFileCount=[int]$overwrittenFiles.Count
        SkippedFileCount=[int]$skippedFiles.Count
        SkippedFiles=$skippedFiles.ToArray()
    }
}

function Write-ToolDataStateAtomic {
    param([Parameter(Mandatory = $true)][object]$State)
    $root = Get-ToolDataRoot
    $statePath = Join-Path $root "data-state.json"
    [void](Assert-ToolDataPathWithinRoot -Path $statePath -Root $root)
    $temporary = Join-Path $root (".data-state-" + [Guid]::NewGuid().ToString("N") + ".tmp")
    try {
        [IO.File]::WriteAllText($temporary, ($State | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $temporary -Destination $statePath -Force -ErrorAction Stop
    } finally {
        if (Test-Path -LiteralPath $temporary -PathType Leaf) { Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue }
    }
}

function Initialize-ToolDataLifecycle {
    [CmdletBinding()]
    param([switch]$SkipMigration)

    $root = Get-ToolDataRoot
    if ($script:ToolDataLifecycleState -and
        [string]::Equals($script:ToolDataInitializedRoot, $root, [StringComparison]::OrdinalIgnoreCase)) {
        return $script:ToolDataLifecycleState
    }

    $mutex = New-Object Threading.Mutex($false, $script:ToolDataMigrationMutexName)
    $lockTaken = $false
    try {
        try { $lockTaken = $mutex.WaitOne([TimeSpan]::FromSeconds(30)) }
        catch [Threading.AbandonedMutexException] { $lockTaken = $true }
        if (-not $lockTaken) { throw "Hết thời gian chờ khóa migration dữ liệu v4.6." }

        New-ToolDataDirectorySafe -Path $root
        $env:TOOL_DATA_ROOT = $root
        $env:TOOL_DATA_SCHEMA_VERSION = $script:ToolDataSchemaVersion
        $statePath = Join-Path $root "data-state.json"
        if (Test-Path -LiteralPath $statePath -PathType Leaf) {
            if (Test-ToolDataReparsePoint -Path $statePath) { throw "data-state.json không an toàn." }
            $stateItem = Get-Item -LiteralPath $statePath -Force -ErrorAction Stop
            if ($stateItem.Length -le 0 -or $stateItem.Length -gt 1048576) { throw "data-state.json có kích thước không hợp lệ." }
            $state = Get-Content -LiteralPath $statePath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            if ([string]$state.DataSchemaVersion -ne $script:ToolDataSchemaVersion) {
                throw "DataSchemaVersion không tương thích: $([string]$state.DataSchemaVersion); yêu cầu $($script:ToolDataSchemaVersion)."
            }
            if ([string]$state.StorageGeneration -ne $script:ToolDataStorageGeneration) {
                throw "StorageGeneration không tương thích: $([string]$state.StorageGeneration)."
            }
            if ([string]$state.MigrationStatus -eq 'Partial') {
                throw "Migration dữ liệu trước đó chưa hoàn tất; v4.6 từ chối ghi để tránh dùng trạng thái một phần."
            }
            if (-not $state.PSObject.Properties['ProducerVersion']) {
                $producerVersion = if ($state.PSObject.Properties['ProductVersion']) { [string]$state.ProductVersion } else { $script:ToolDataToolVersion }
                $state | Add-Member -NotePropertyName ProducerVersion -NotePropertyValue $producerVersion
                Write-ToolDataStateAtomic -State $state
            }
            $script:ToolDataInitializedRoot = $root
            $script:ToolDataLifecycleState = $state
            return $state
        }

        $legacyRoot = Get-ToolLegacyDataRoot
        $migrationItems = New-Object System.Collections.Generic.List[object]
        $migrationStatus = "Fresh"
        $migrationError = ""
        $migrationVerified = $false
        $migrationTransactionId = ""
        $allowMigration = [bool](-not $SkipMigration -and [string]$env:TOOL_DATA_LIFECYCLE_SKIP_MIGRATION -ne "1")
        if ($allowMigration -and (Test-Path -LiteralPath $legacyRoot -PathType Container)) {
            if (Test-ToolDataReparsePoint -Path $legacyRoot) { throw "Vùng dữ liệu cũ là reparse point: $legacyRoot" }
            $migrationTransactionId = [Guid]::NewGuid().ToString('N')
            $stagingRoot = Join-Path $root ('.migration-' + $migrationTransactionId)
            New-ToolDataDirectorySafe -Path $stagingRoot
            try {
                foreach ($relative in @("approved-kms-servers.txt", "enterprise-network-settings.json", "plugins", "timeline", "enterprise")) {
                    $source = Join-Path $legacyRoot $relative
                    if (-not (Test-Path -LiteralPath $source)) { continue }
                    $staged = Join-Path $stagingRoot $relative
                    $copy = Copy-ToolDataTreeNoOverwrite -Source $source -Destination $staged
                    Assert-ToolDataMigrationCopy -Source $source -Destination $staged
                    [void]$migrationItems.Add([pscustomobject][ordered]@{
                        RelativePath=$relative; CopiedFiles=[int]$copy.CopiedFiles; CopiedBytes=[int64]$copy.CopiedBytes; Verified=$true
                    })
                }
                $commit = Merge-ToolDataMigrationStaging -StagingRoot $stagingRoot -DestinationRoot $root
                $migrationVerified = $true
                $migrationStatus = "Migrated"
                foreach ($item in $migrationItems) {
                    $item | Add-Member -NotePropertyName CommitCreatedFiles -NotePropertyValue ([int]$commit.CreatedFileCount) -Force
                    $item | Add-Member -NotePropertyName CommitOverwrittenFiles -NotePropertyValue ([int]$commit.OverwrittenFileCount) -Force
                    $item | Add-Member -NotePropertyName CommitSkippedFiles -NotePropertyValue ([int]$commit.SkippedFileCount) -Force
                }
            } catch {
                $migrationError = ([string]$_.Exception.Message).Replace("`r", " ").Replace("`n", " ")
                throw "Migration dữ liệu v4.6 thất bại; dữ liệu cũ vẫn nguyên vẹn và thay đổi mới đã được hoàn tác: $migrationError"
            } finally {
                if (Test-Path -LiteralPath $stagingRoot -PathType Container) {
                    [void](Assert-ToolDataPathWithinRoot -Path $stagingRoot -Root $root)
                    Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        } elseif (-not $allowMigration -and (Test-Path -LiteralPath $legacyRoot -PathType Container)) {
            $migrationStatus = "Skipped"
        }

        $now = [DateTime]::UtcNow.ToString("o")
        $state = [pscustomobject][ordered]@{
            SchemaVersion = $script:ToolDataStateSchemaVersion
            DataSchemaVersion = $script:ToolDataSchemaVersion
            ProductVersion = $script:ToolDataToolVersion
            ProducerVersion = $script:ToolDataToolVersion
            StorageGeneration = $script:ToolDataStorageGeneration
            CreatedAtUtc = $now
            LastMigratedAtUtc = $(if ($migrationStatus -eq "Migrated") { $now } else { "" })
            MigrationStatus = $migrationStatus
            MigrationError = $migrationError
            MigrationTransactionId = $migrationTransactionId
            MigrationVerified = [bool]$migrationVerified
            LegacyDataPreserved = $true
            MigratedFrom = $(if ($migrationStatus -eq "Migrated") { $legacyRoot } else { "" })
            MigratedItems = $migrationItems.ToArray()
            LegacyReadOnlyRoots = @(
                (Join-Path $legacyRoot "backups"),
                (Join-Path $legacyRoot "logs")
            )
            ConcurrencyPolicy = "v4.6 uses a separate data root; launcher detects active v4.4/v4.5 mutexes before migration. Do not run versions concurrently."
        }
        Write-ToolDataStateAtomic -State $state
        $script:ToolDataInitializedRoot = $root
        $script:ToolDataLifecycleState = $state
        return $state
    } finally {
        if ($lockTaken) { try { $mutex.ReleaseMutex() } catch {} }
        $mutex.Dispose()
    }
}

function Get-ToolDataLifecycleMetadata {
    $state = Initialize-ToolDataLifecycle
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolDataStateSchemaVersion
        DataSchemaVersion = $script:ToolDataSchemaVersion
        ToolVersion = $script:ToolDataToolVersion
        ProducerVersion = [string]$state.ProducerVersion
        StorageGeneration = $script:ToolDataStorageGeneration
        DataRoot = Get-ToolDataRoot
        LegacyDataRoot = Get-ToolLegacyDataRoot
        MigrationStatus = [string]$state.MigrationStatus
        ConcurrencyPolicy = [string]$state.ConcurrencyPolicy
    }
}
