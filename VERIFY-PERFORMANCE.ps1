[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("Tool-Kiem-Tra-v4.4-performance-" + [Guid]::NewGuid().ToString('N'))

function Add-Failure([string]$Message) { [void]$failures.Add($Message) }

try {
    $helperPath = Join-Path $root 'Tool-ScanOptimization.ps1'
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'Missing Tool-ScanOptimization.ps1.' }
    . $helperPath

    $metadata = Get-ToolScanOptimizationMetadata
    if ([string]$metadata.Version -ne '1.0' -or [string]$metadata.ToolVersion -ne '4.4' -or
        -not [bool]$metadata.PreservesExistingScanRoots -or [int]$metadata.OfficeStatusThrottle -gt 3 -or
        [int]$metadata.FileScanThrottle -gt 4) {
        Add-Failure 'Scan optimization metadata does not match the v4.4 contract.'
    }

    $rootOne = Join-Path $tempRoot 'disk-one'
    $rootTwo = Join-Path $tempRoot 'disk-two'
    [void](New-Item -ItemType Directory -Path (Join-Path $rootOne 'nested') -Force)
    [void](New-Item -ItemType Directory -Path $rootTwo -Force)
    [IO.File]::WriteAllText((Join-Path $rootOne 'nested\kms-tool.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $rootTwo 'activator-readme.txt'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $rootTwo 'normal.txt'), 'fixture')

    $matches = @(Find-ToolPatternFilesParallel -Roots @($rootOne, $rootTwo) -Pattern '(?i)(kms|activator)' -MaximumResults 10 -ThrottleLimit 2)
    $unexpectedMatches = @($matches | Where-Object { $_ -notmatch '(kms-tool|activator-readme)' })
    if ($matches.Count -ne 2 -or $unexpectedMatches.Count -ne 0) {
        Add-Failure 'Parallel file scan did not return the expected multi-root fixtures.'
    }
    $officeResults = @(Invoke-ToolParallelOfficeStatus -CscriptPath "$env:SystemRoot\System32\cscript.exe" -OsppPaths @() -ThrottleLimit 2)
    if ($officeResults.Count -ne 0) {
        Add-Failure 'Parallel Office scan did not handle an empty input list.'
    }

    $inventoryText = Get-Content -LiteralPath (Join-Path $root 'kiem-tra-cau-hinh-ban-quyen.ps1') -Raw -Encoding UTF8
    $cleanupText = Get-Content -LiteralPath (Join-Path $root 'windows-license-compliance-cleanup.ps1') -Raw -Encoding UTF8
    foreach ($pattern in @('Get-ToolOptimizedOfficeOsppPaths','Invoke-ToolParallelOfficeStatus')) {
        if ($inventoryText -notmatch $pattern -or $cleanupText -notmatch $pattern) {
            Add-Failure "Office flow does not use optimization helper: $pattern"
        }
    }
    if ($inventoryText -notmatch 'Find-ToolPatternFilesParallel') {
        Add-Failure 'Inventory flow does not use parallel per-root file scanning.'
    }
} catch {
    Add-Failure $_.Exception.Message
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedTemp).StartsWith('Tool-Kiem-Tra-v4.4-performance-', [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedTemp -Recurse -Force
        }
    }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-PERFORMANCE: FAILED ($($failures.Count) errors)"
    exit 1
}

Write-Host 'VERIFY-PERFORMANCE: PASSED' -ForegroundColor Green
exit 0
