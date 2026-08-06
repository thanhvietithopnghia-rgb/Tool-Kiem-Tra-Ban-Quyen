[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$sourceRoot = [IO.Path]::GetFullPath($SourceDirectory)
$modulePath = Join-Path $sourceRoot 'Tool-DataLifecycle.ps1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw 'Thiếu Tool-DataLifecycle.ps1.' }

function Assert-DataLifecycle {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$temporaryParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$fixtureRoot = Join-Path $temporaryParent ('ToolDataLifecycleVerifier-' + [Guid]::NewGuid().ToString('N'))
$oldDataRoot = [string]$env:TOOL_DATA_ROOT
$oldLegacyRoot = [string]$env:TOOL_LEGACY_DATA_ROOT
$oldSkipMigration = [string]$env:TOOL_DATA_LIFECYCLE_SKIP_MIGRATION
try {
    $dataRoot = Join-Path $fixtureRoot 'success\v4.6'
    $legacyRoot = Join-Path $fixtureRoot 'success\v4.4'
    New-Item -ItemType Directory -Path (Join-Path $dataRoot 'plugins') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'plugins') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'logs') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $legacyRoot 'backups') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dataRoot 'approved-kms-servers.txt') -Value 'bundled.example' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $dataRoot 'plugins\builtin.json') -Value '{"generation":"v4.6"}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $legacyRoot 'approved-kms-servers.txt') -Value 'legacy.example' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $legacyRoot 'plugins\custom.json') -Value '{"custom":true}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $legacyRoot 'plugins\builtin.json') -Value '{"generation":"v4.4"}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $legacyRoot 'logs\legacy.jsonl') -Value '{}' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $legacyRoot 'backups\legacy.txt') -Value 'legacy' -Encoding ASCII

    $env:TOOL_DATA_ROOT = $dataRoot
    $env:TOOL_LEGACY_DATA_ROOT = $legacyRoot
    $env:TOOL_DATA_LIFECYCLE_SKIP_MIGRATION = '0'
    . $modulePath
    $state = Initialize-ToolDataLifecycle
    Assert-DataLifecycle ([string]$state.DataSchemaVersion -eq '2.0') 'Sai DataSchemaVersion.'
    Assert-DataLifecycle ([string]$state.ProducerVersion -eq '4.6.0.0') 'Thiếu ProducerVersion v4.6.0.0.'
    Assert-DataLifecycle ([string]$state.StorageGeneration -eq 'v4.6') 'Sai StorageGeneration.'
    Assert-DataLifecycle ([string]$state.MigrationStatus -eq 'Migrated' -and [bool]$state.MigrationVerified) 'Migration chưa được xác minh.'
    Assert-DataLifecycle ([bool]$state.LegacyDataPreserved) 'Migration không công bố việc giữ nguyên dữ liệu cũ.'
    Assert-DataLifecycle ((Get-Content -LiteralPath (Join-Path $dataRoot 'approved-kms-servers.txt') -Raw).Trim() -eq 'legacy.example') 'Cấu hình KMS cũ không được ưu tiên khi migrate.'
    Assert-DataLifecycle (Test-Path -LiteralPath (Join-Path $dataRoot 'plugins\custom.json') -PathType Leaf) 'Plugin tùy chỉnh không được migrate.'
    Assert-DataLifecycle ((Get-Content -LiteralPath (Join-Path $dataRoot 'plugins\builtin.json') -Raw).Trim() -eq '{"generation":"v4.6"}') 'Migration đã ghi đè plugin tích hợp mới.'
    Assert-DataLifecycle (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'logs\legacy.jsonl'))) 'Log cũ không được tự sao chép vào vùng ghi v4.6.'
    Assert-DataLifecycle (-not (Test-Path -LiteralPath (Join-Path $dataRoot 'backups\legacy.txt'))) 'Backup cũ không được tự sao chép vào vùng ghi v4.6.'
    Assert-DataLifecycle (Test-Path -LiteralPath (Join-Path $legacyRoot 'plugins\custom.json') -PathType Leaf) 'Migration đã thay đổi dữ liệu cũ.'
    Assert-DataLifecycle (Test-Path -LiteralPath (Join-Path $dataRoot 'data-state.json') -PathType Leaf) 'Thiếu data-state.json.'

    Set-Content -LiteralPath (Join-Path $legacyRoot 'approved-kms-servers.txt') -Value 'changed-after-migration.example' -Encoding ASCII
    $stateAgain = Initialize-ToolDataLifecycle
    Assert-DataLifecycle ([string]$stateAgain.MigrationTransactionId -eq [string]$state.MigrationTransactionId) 'Khởi tạo lặp lại đã chạy migration lần hai.'
    Assert-DataLifecycle ((Get-Content -LiteralPath (Join-Path $dataRoot 'approved-kms-servers.txt') -Raw).Trim() -eq 'legacy.example') 'Khởi tạo lặp lại đã ghi đè cấu hình đã migrate.'

    $rollbackDataRoot = Join-Path $fixtureRoot 'rollback\v4.6'
    $rollbackLegacyRoot = Join-Path $fixtureRoot 'rollback\v4.4'
    New-Item -ItemType Directory -Path (Join-Path $rollbackDataRoot 'plugins\custom.json') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $rollbackLegacyRoot 'plugins') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $rollbackDataRoot 'approved-kms-servers.txt') -Value 'bundled.example' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $rollbackLegacyRoot 'approved-kms-servers.txt') -Value 'legacy.example' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $rollbackLegacyRoot 'plugins\custom.json') -Value '{"custom":true}' -Encoding ASCII
    $env:TOOL_DATA_ROOT = $rollbackDataRoot
    $env:TOOL_LEGACY_DATA_ROOT = $rollbackLegacyRoot
    . $modulePath
    $migrationFailed = $false
    try { [void](Initialize-ToolDataLifecycle) } catch { $migrationFailed = $true }
    Assert-DataLifecycle $migrationFailed 'Fixture lỗi không làm migration fail-closed.'
    Assert-DataLifecycle ((Get-Content -LiteralPath (Join-Path $rollbackDataRoot 'approved-kms-servers.txt') -Raw).Trim() -eq 'bundled.example') 'Rollback không khôi phục tệp bị ghi đè.'
    Assert-DataLifecycle (-not (Test-Path -LiteralPath (Join-Path $rollbackDataRoot 'data-state.json'))) 'Migration lỗi vẫn ghi trạng thái hoàn tất.'
    Assert-DataLifecycle (@(Get-ChildItem -LiteralPath $rollbackDataRoot -Directory -Filter '.migration-*' -ErrorAction SilentlyContinue).Count -eq 0) 'Migration lỗi để lại staging.'

    Write-Host 'VERIFY-DATA-LIFECYCLE: OK (schema 2.0 + verified one-time migration + legacy preservation + rollback)'
} finally {
    $env:TOOL_DATA_ROOT = $oldDataRoot
    $env:TOOL_LEGACY_DATA_ROOT = $oldLegacyRoot
    $env:TOOL_DATA_LIFECYCLE_SKIP_MIGRATION = $oldSkipMigration
    $resolvedFixture = [IO.Path]::GetFullPath($fixtureRoot)
    if ($resolvedFixture.StartsWith($temporaryParent, [StringComparison]::OrdinalIgnoreCase) -and
        -not [string]::Equals($resolvedFixture, $temporaryParent, [StringComparison]::OrdinalIgnoreCase) -and
        (Test-Path -LiteralPath $resolvedFixture -PathType Container)) {
        Remove-Item -LiteralPath $resolvedFixture -Recurse -Force -ErrorAction SilentlyContinue
    }
}
