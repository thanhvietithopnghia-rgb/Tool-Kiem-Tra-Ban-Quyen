$script:ToolScanOptimizationVersion = "1.0"
$script:ToolScanOptimizationToolVersion = "4.4"

function Get-ToolOptimizedOfficeOsppPaths {
    [CmdletBinding()]
    param([ValidateRange(1, 6)][int]$MaximumDepth = 3)

    $result = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) |
        Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
        ForEach-Object { [IO.Path]::GetFullPath([string]$_) } |
        Select-Object -Unique
    $knownRelativePaths = @(
        "Microsoft Office\Office16\OSPP.VBS",
        "Microsoft Office\root\Office16\OSPP.VBS",
        "Microsoft Office\Office15\OSPP.VBS",
        "Microsoft Office\root\Office15\OSPP.VBS",
        "Microsoft Office\Office14\OSPP.VBS",
        "Microsoft Office\root\Office14\OSPP.VBS"
    )

    foreach ($root in $roots) {
        foreach ($relativePath in $knownRelativePaths) {
            $candidate = Join-Path $root $relativePath
            if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) { continue }
            $fullPath = [IO.Path]::GetFullPath($candidate)
            $key = $fullPath.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [void]$result.Add($fullPath)
            }
        }

        $officeRoot = Join-Path $root "Microsoft Office"
        if (-not (Test-Path -LiteralPath $officeRoot -PathType Container)) { continue }
        $queue = New-Object "System.Collections.Generic.Queue[object]"
        $queue.Enqueue([pscustomobject]@{ Path=[IO.Path]::GetFullPath($officeRoot); Depth=0 })
        while ($queue.Count -gt 0) {
            $entry = $queue.Dequeue()
            try {
                $directoryInfo = New-Object IO.DirectoryInfo([string]$entry.Path)
                if (($directoryInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                foreach ($file in @($directoryInfo.GetFiles("OSPP.VBS", [IO.SearchOption]::TopDirectoryOnly))) {
                    $fullPath = $file.FullName
                    $key = $fullPath.ToLowerInvariant()
                    if (-not $seen.ContainsKey($key)) {
                        $seen[$key] = $true
                        [void]$result.Add($fullPath)
                    }
                }
                if ([int]$entry.Depth -ge $MaximumDepth) { continue }
                foreach ($child in @($directoryInfo.GetDirectories())) {
                    if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                        $queue.Enqueue([pscustomobject]@{ Path=$child.FullName; Depth=([int]$entry.Depth + 1) })
                    }
                }
            } catch {}
        }
    }
    return @($result.ToArray() | Sort-Object)
}

function Invoke-ToolParallelOfficeStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$CscriptPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$OsppPaths,
        [ValidateRange(1, 8)][int]$ThrottleLimit = 3
    )

    $paths = @($OsppPaths | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -Unique)
    if ($paths.Count -eq 0) { return @() }
    $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($ThrottleLimit, $paths.Count))
    $workers = New-Object System.Collections.Generic.List[object]
    $workerScript = @'
param($NativeCscriptPath,$OsppPath)
$primary = @(& $NativeCscriptPath //nologo $OsppPath /dstatusall 2>$null)
$output = ($primary -join "`n")
$usedFallback = $false
if ([string]::IsNullOrWhiteSpace($output) -or $output -notmatch '(?im)^\s*(?:SKU ID|LICENSE NAME)\s*:') {
    $fallback = @(& $NativeCscriptPath //nologo $OsppPath /dstatus 2>$null)
    $output = ($fallback -join "`n")
    $usedFallback = $true
}
[pscustomobject][ordered]@{
    Path = $OsppPath
    Output = $output
    UsedFallback = $usedFallback
    Readable = [bool](-not [string]::IsNullOrWhiteSpace($output) -and $output -match '(?im)^\s*(?:SKU ID|LICENSE NAME|LICENSE STATUS)\s*:')
}
'@

    try {
        $pool.Open()
        foreach ($path in $paths) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($workerScript).AddArgument($CscriptPath).AddArgument([string]$path)
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $result = New-Object System.Collections.Generic.List[object]
        foreach ($worker in $workers) {
            try {
                foreach ($item in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if ($null -ne $item) { [void]$result.Add($item) }
                }
            } finally {
                $worker.PowerShell.Dispose()
            }
        }
        return @($result.ToArray() | Sort-Object Path)
    } finally {
        foreach ($worker in $workers) {
            try { $worker.PowerShell.Dispose() } catch {}
        }
        try { $pool.Close() } catch {}
        $pool.Dispose()
    }
}

function Find-ToolPatternFilesParallel {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Roots,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [ValidateRange(1, 1000)][int]$MaximumResults = 60,
        [ValidateRange(1, 8)][int]$ThrottleLimit = 4
    )

    $scanRoots = @($Roots | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | ForEach-Object { [IO.Path]::GetFullPath($_) } | Select-Object -Unique)
    if ($scanRoots.Count -eq 0) { return @() }
    [void](New-Object Text.RegularExpressions.Regex($Pattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromMilliseconds(500)))
    $pool = [RunspaceFactory]::CreateRunspacePool(1, [Math]::Min($ThrottleLimit, $scanRoots.Count))
    $workers = New-Object System.Collections.Generic.List[object]
    $workerScript = @'
param($Root,$RegexPattern,$MaximumPerRoot)
$regex = New-Object Text.RegularExpressions.Regex($RegexPattern, [Text.RegularExpressions.RegexOptions]::IgnoreCase, [TimeSpan]::FromMilliseconds(500))
$matches = New-Object System.Collections.Generic.List[string]
$pending = New-Object "System.Collections.Generic.Stack[string]"
$pending.Push($Root)
while ($pending.Count -gt 0 -and $matches.Count -lt $MaximumPerRoot) {
    $current = $pending.Pop()
    try {
        $directory = New-Object IO.DirectoryInfo($current)
        if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        foreach ($file in $directory.EnumerateFiles()) {
            if ($regex.IsMatch($file.Name) -or $regex.IsMatch($file.FullName)) {
                [void]$matches.Add($file.FullName)
                if ($matches.Count -ge $MaximumPerRoot) { break }
            }
        }
        if ($matches.Count -ge $MaximumPerRoot) { break }
        foreach ($child in $directory.EnumerateDirectories()) {
            if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { $pending.Push($child.FullName) }
        }
    } catch {}
}
$matches.ToArray()
'@

    try {
        $pool.Open()
        foreach ($root in $scanRoots) {
            $powerShell = [PowerShell]::Create()
            $powerShell.RunspacePool = $pool
            [void]$powerShell.AddScript($workerScript).AddArgument([string]$root).AddArgument($Pattern).AddArgument($MaximumResults)
            $handle = $powerShell.BeginInvoke()
            [void]$workers.Add([pscustomobject]@{ PowerShell=$powerShell; Handle=$handle })
        }
        $paths = New-Object System.Collections.Generic.List[string]
        foreach ($worker in $workers) {
            try {
                foreach ($path in @($worker.PowerShell.EndInvoke($worker.Handle))) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$path)) { [void]$paths.Add([string]$path) }
                }
            } finally {
                $worker.PowerShell.Dispose()
            }
        }
        return @($paths.ToArray() | Select-Object -Unique | Sort-Object | Select-Object -First $MaximumResults)
    } finally {
        foreach ($worker in $workers) {
            try { $worker.PowerShell.Dispose() } catch {}
        }
        try { $pool.Close() } catch {}
        $pool.Dispose()
    }
}

function Get-ToolScanOptimizationMetadata {
    return [pscustomobject][ordered]@{
        Version = $script:ToolScanOptimizationVersion
        ToolVersion = $script:ToolScanOptimizationToolVersion
        OfficeDiscovery = "BoundedDepth"
        OfficeStatusThrottle = 3
        FileScanThrottle = 4
        PreservesExistingScanRoots = $true
    }
}
