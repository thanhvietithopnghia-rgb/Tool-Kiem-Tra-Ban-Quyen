[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("Tool-Kiem-Tra-v4.8-performance-" + [Guid]::NewGuid().ToString('N'))

function Add-Failure([string]$Message) { [void]$failures.Add($Message) }

try {
    $helperPath = Join-Path $root 'Tool-ScanOptimization.ps1'
    if (-not (Test-Path -LiteralPath $helperPath -PathType Leaf)) { throw 'Missing Tool-ScanOptimization.ps1.' }
    . $helperPath
    $softwareInventoryPath = Join-Path $root 'Tool-SoftwareInventory.ps1'
    if (-not (Test-Path -LiteralPath $softwareInventoryPath -PathType Leaf)) { throw 'Missing Tool-SoftwareInventory.ps1.' }
    . $softwareInventoryPath

    $metadata = Get-ToolScanOptimizationMetadata
if ([string]$metadata.Version -ne '1.0' -or [string]$metadata.ToolVersion -ne '4.8' -or
        -not [bool]$metadata.PreservesExistingScanRoots -or [int]$metadata.OfficeStatusThrottle -gt 3 -or
        [int]$metadata.FileScanThrottle -gt 4 -or [int]$metadata.FileScanMaximumDepth -ne 4 -or
        [int]$metadata.FileScanPerRootTimeoutSeconds -ne 12) {
        Add-Failure 'Scan optimization metadata does not match the v4.8 contract.'
    }

    $rootOne = Join-Path $tempRoot 'disk-one'
    $rootTwo = Join-Path $tempRoot 'disk-two'
    [void](New-Item -ItemType Directory -Path (Join-Path $rootOne 'nested') -Force)
    [void](New-Item -ItemType Directory -Path $rootTwo -Force)
    [IO.File]::WriteAllText((Join-Path $rootOne 'nested\kms-tool.exe'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $rootTwo 'activator-readme.txt'), 'fixture')
    [IO.File]::WriteAllText((Join-Path $rootTwo 'normal.txt'), 'fixture')
    $tooDeep = Join-Path $rootOne 'd1\d2\d3\d4\d5'
    [void](New-Item -ItemType Directory -Path $tooDeep -Force)
    [IO.File]::WriteAllText((Join-Path $tooDeep 'activator-too-deep.txt'), 'fixture')

    $matches = @(Find-ToolPatternFilesParallel -Roots @($rootOne, $rootTwo) -Pattern '(?i)(kms|activator)' -MaximumResults 10 -ThrottleLimit 2)
    $unexpectedMatches = @($matches | Where-Object { $_ -notmatch '(kms-tool|activator-readme)' })
    if ($matches.Count -ne 2 -or $unexpectedMatches.Count -ne 0) {
        Add-Failure 'Parallel file scan did not return the expected multi-root fixtures.'
    }
    $officeResults = @(Invoke-ToolParallelOfficeStatus -CscriptPath "$env:SystemRoot\System32\cscript.exe" -OsppPaths @() -ThrottleLimit 2)
    if ($officeResults.Count -ne 0) {
        Add-Failure 'Parallel Office scan did not handle an empty input list.'
    }

    $signatureRoot = Join-Path $tempRoot 'signature-batch'
    [void](New-Item -ItemType Directory -Path $signatureRoot -Force)
    $signaturePaths = New-Object System.Collections.Generic.List[string]
    foreach ($index in 1..6) {
        $signaturePath = Join-Path $signatureRoot ("fixture-$index.exe")
        [IO.File]::WriteAllText($signaturePath, ("unsigned-fixture-$index"), (New-Object Text.UTF8Encoding($false)))
        $signaturePaths.Add($signaturePath)
    }
    $script:ToolSoftwareSignatureCache = @{}
    $signatureResults = Get-ToolSoftwareSignatureStatesParallel -Paths $signaturePaths.ToArray() -ThrottleLimit 2
    $signatureCacheCount = $script:ToolSoftwareSignatureCache.Count
    $cachedSignatureResults = Get-ToolSoftwareSignatureStatesParallel -Paths $signaturePaths.ToArray() -ThrottleLimit 2
    if ($signatureResults.Count -ne $signaturePaths.Count -or $cachedSignatureResults.Count -ne $signaturePaths.Count -or
        $signatureCacheCount -ne $signaturePaths.Count -or $script:ToolSoftwareSignatureCache.Count -ne $signatureCacheCount) {
        Add-Failure 'Parallel Authenticode batching or its stable file cache is not working.'
    }
    $deepMetadata = Get-ToolSoftwareLastDeepScanMetadata
    foreach ($propertyName in @('UniqueDirectoriesScanned','DirectoryCacheHits')) {
        if ($null -eq $deepMetadata.PSObject.Properties[$propertyName]) {
            Add-Failure "Deep-scan performance metadata is missing: $propertyName"
        }
    }

    # Regression for the v4.8 inventory merge hot path: every synthetic product
    # is discovered twice but must keep one identical logical result.
    $syntheticRecords = New-Object System.Collections.Generic.List[object]
    foreach ($index in 1..240) {
        # A distinct leading token exercises the indexed name-bucket path while
        # the duplicate Registry/Shortcut pair still validates merge parity.
        $name = 'PerformanceFixture{0:d3} Product' -f $index
        $location = 'C:\Program Files\PerformanceFixture\{0:d3}' -f $index
        foreach ($source in @('Registry','Shortcut')) {
            $syntheticRecords.Add([pscustomobject][ordered]@{
                Id=('{0}-{1}' -f $index,$source); Name=$name; Version=('1.0.{0}' -f $index); Publisher='VIETIT Fixture'
                InstallDate=''; InstallLocation=$location; DisplayIcon=''; UninstallString=''; RegistryPath=''
                Scope='Machine64'; Architecture='64-bit'; SourceKind=$source; RepresentativePath=(Join-Path $location 'fixture.exe')
                SourceDetail=$source; SignaturePublisher=''; FileVersion=''; DiscoverySources=@($source)
                IsSystemComponent=$false; SystemComponentReason=''; ReleaseType=''; NonRemovable=$false
            })
        }
    }
    $mergeWatch = [Diagnostics.Stopwatch]::StartNew()
    $syntheticMerged = @(Merge-ToolSoftwareInventoryRecords -Records $syntheticRecords.ToArray())
    $mergeWatch.Stop()
    if ($syntheticMerged.Count -ne 240 -or @($syntheticMerged | Where-Object { [int]$_.MergedRecordCount -ne 2 }).Count -gt 0) {
        Add-Failure 'Optimized software merge changed the logical deduplication result.'
    }
    if ($mergeWatch.Elapsed.TotalSeconds -gt 12) {
        Add-Failure ('Optimized software merge exceeded the bounded regression budget: {0:N2}s.' -f $mergeWatch.Elapsed.TotalSeconds)
    }

    $inventoryText = Get-Content -LiteralPath (Join-Path $root 'kiem-tra-cau-hinh-ban-quyen.ps1') -Raw -Encoding UTF8
    $cleanupText = Get-Content -LiteralPath (Join-Path $root 'windows-license-compliance-cleanup.ps1') -Raw -Encoding UTF8
    $softwareInventoryText = Get-Content -LiteralPath $softwareInventoryPath -Raw -Encoding UTF8
    foreach ($pattern in @('Get-ToolOptimizedOfficeOsppPaths','Invoke-ToolParallelOfficeStatus')) {
        if ($inventoryText -notmatch $pattern -or $cleanupText -notmatch $pattern) {
            Add-Failure "Office flow does not use optimization helper: $pattern"
        }
    }
    if ($inventoryText -notmatch 'Find-ToolPatternFilesParallel') {
        Add-Failure 'Inventory flow does not use parallel per-root file scanning.'
    }
    if ($inventoryText -notmatch 'Text\.StringBuilder' -or $inventoryText -notmatch 'reportPresentationCache' -or
        $inventoryText -notmatch 'reportLiteralTranslationMaps' -or $inventoryText -notmatch 'scheduledTaskObjectsAll') {
        Add-Failure 'Large software reports do not use bounded table construction and presentation-text caching.'
    }
    foreach ($requiredToken in @(
        'Get-ToolSoftwareSignatureStatesParallel','ToolSoftwareDeepDirectoryCache','EnumerateFileSystemInfos',
        'CreateRunspacePool(1, 4)','New-ToolSoftwareMergeDescriptor','quickSignatureResults',
        'NameBucket','clustersByNameBucket','externalEvidenceByApplication','externalEvidenceByVendor','resultData'
    )) {
        if ($softwareInventoryText -notmatch [regex]::Escape($requiredToken)) {
            Add-Failure "Universal deep scan is missing the speed contract: $requiredToken"
        }
    }
    if ($softwareInventoryText -notmatch 'desiredSignatureLimit\s*=\s*if\s*\([^\r\n]+\)\s*\{\s*6\s*\}\s*elseif\s*\([^\r\n]+\)\s*\{\s*3\s*\}\s*else\s*\{\s*1\s*\}') {
        Add-Failure 'Adaptive per-application signature profile is not 6/3/1.'
    }
} catch {
    Add-Failure $_.Exception.Message
} finally {
    if (Test-Path -LiteralPath $tempRoot -PathType Container) {
        $resolvedTemp = [IO.Path]::GetFullPath($tempRoot)
        $systemTemp = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
        if ($resolvedTemp.StartsWith($systemTemp, [StringComparison]::OrdinalIgnoreCase) -and
            [IO.Path]::GetFileName($resolvedTemp).StartsWith('Tool-Kiem-Tra-v4.8-performance-', [StringComparison]::OrdinalIgnoreCase)) {
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
