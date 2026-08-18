param()

if ($PSVersionTable.PSVersion.Major -lt 3) { exit 10 }

$script:localLicenseVersion = "4.8.0.1"
$localizationHelper = Join-Path $PSScriptRoot "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { exit 12 }
. $localizationHelper
$script:localLicenseCulture = Get-ToolCulture
$env:TOOL_UI_CULTURE = $script:localLicenseCulture

function Get-LocalLicenseText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    return Get-ToolText -Key $Key -Culture $script:localLicenseCulture -FormatArguments $Arguments
}

$runtimeHelper = Join-Path $PSScriptRoot "Tool-Runtime.ps1"
try {
    if (-not (Test-Path -LiteralPath $runtimeHelper -PathType Leaf)) { throw (Get-LocalLicenseText "localLicense.error.runtimeMissing") }
    . $runtimeHelper
    [void](Assert-ToolNativeArchitecture)
    $nativeCscriptPath = Get-ToolNativeSystemPath "cscript.exe"
} catch {
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, (Get-LocalLicenseText "localLicense.error.runtimeTitle"), "OK", "Warning") | Out-Null
    exit 12
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)
[System.Windows.Forms.Application]::EnableVisualStyles()
$uiThemeHelper = Join-Path $PSScriptRoot "Tool-UiTheme.ps1"
if (-not (Test-Path -LiteralPath $uiThemeHelper -PathType Leaf)) {
    [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.error.themeMissing"), (Get-LocalLicenseText "localLicense.error.incompleteTitle"), "OK", "Error") | Out-Null
    exit 12
}
. $uiThemeHelper
$script:localLicenseTheme = Get-ToolUiTheme
$offlinePolicyHelper = Join-Path $PSScriptRoot "Tool-OfflinePolicy.ps1"
$compatibilityHelper = Join-Path $PSScriptRoot "Tool-Compatibility.ps1"
if (-not (Test-Path -LiteralPath $offlinePolicyHelper -PathType Leaf) -or -not (Test-Path -LiteralPath $compatibilityHelper -PathType Leaf)) {
    [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.error.foundationMissing"), (Get-LocalLicenseText "localLicense.error.incompleteTitle"), "OK", "Error") | Out-Null
    exit 12
}
. $offlinePolicyHelper
. $compatibilityHelper
$script:localOfflineMode = [bool](-not (Test-ToolEnterpriseNetworkActionAllowed))
$script:officeCompatibility = Get-ToolOfficeCompatibilityProfile

function Show-LocalOfflineBlocked {
    param([string]$Action)
    [System.Windows.Forms.MessageBox]::Show(
        (Get-LocalLicenseText "localLicense.blocked.message" @($Action)),
        (Get-LocalLicenseText "localLicense.blocked.title"),
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
}

function Test-IsAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if ([string]$env:TOOL_UI_SMOKE_TEST -ne "1" -and -not (Test-IsAdministrator)) {
    [System.Windows.Forms.MessageBox]::Show(
        (Get-LocalLicenseText "localLicense.error.adminRequired"),
        (Get-LocalLicenseText "localLicense.error.adminTitle"), "OK", "Warning"
    ) | Out-Null
    exit 20
}

function Normalize-ProductKey([string]$value) {
    $clean = ($value -replace '[^A-Za-z0-9]', '').ToUpperInvariant()
    if ($clean.Length -ne 25) { return "" }
    return (($clean -split '(.{5})' | Where-Object { $_ }) -join '-')
}

function Test-ProductKeyFormat([string]$value) {
    return $value -match '^[A-Z0-9]{5}(-[A-Z0-9]{5}){4}$'
}

function Mask-ProductKey([string]$value) {
    if ($value.Length -lt 5) { return "XXXXX" }
    return "XXXXX-XXXXX-XXXXX-XXXXX-" + $value.Substring($value.Length - 5)
}

function Invoke-CapturedProcess([string]$filePath, [string]$arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $filePath
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    [void]$process.Start()
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        Output = (($stdout, $stderr) -join [Environment]::NewLine).Trim()
    }
}

function Get-WindowsDetails {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue
    $name = if ($cv.ProductName) { [string]$cv.ProductName } else { "Windows" }
    $edition = if ($cv.EditionID) { [string]$cv.EditionID } else { Get-LocalLicenseText "localLicense.unknown" }
    $release = if ($cv.DisplayVersion) { [string]$cv.DisplayVersion } elseif ($cv.ReleaseId) { [string]$cv.ReleaseId } else { "" }
    $build = if ($cv.CurrentBuild) { [string]$cv.CurrentBuild } else { "" }
    return [pscustomobject]@{ Name=$name; Edition=$edition; Release=$release; Build=$build }
}

function Get-WindowsTargetEditions {
    try {
        $result = Invoke-CapturedProcess -FilePath (Get-ToolNativeSystemPath "dism.exe") -Arguments '/Online /English /Get-TargetEditions'
        $targets = @($result.Output -split "`r?`n" | ForEach-Object {
            if ($_ -match 'Target Edition\s*:\s*(\S+)') { $matches[1].Trim() }
        } | Where-Object { $_ } | Select-Object -Unique)
        return $targets
    } catch { return @() }
}

function Get-OfficeOsppPaths {
    $candidates = New-Object System.Collections.ArrayList
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramW6432) | Where-Object { $_ } | Select-Object -Unique
    foreach ($root in $roots) {
        foreach ($relative in @(
            'Microsoft Office\Office16\OSPP.VBS',
            'Microsoft Office\root\Office16\OSPP.VBS',
            'Microsoft Office\Office15\OSPP.VBS'
        )) {
            $path = Join-Path $root $relative
            if (Test-Path -LiteralPath $path) { [void]$candidates.Add($path) }
        }
    }
    if ($candidates.Count -eq 0) {
        foreach ($root in $roots) {
            $officeRoot = Join-Path $root 'Microsoft Office'
            if (Test-Path -LiteralPath $officeRoot) {
                Get-ChildItem -LiteralPath $officeRoot -Recurse -Filter OSPP.VBS -ErrorAction SilentlyContinue | ForEach-Object {
                    [void]$candidates.Add($_.FullName)
                }
            }
        }
    }
    return @($candidates | Select-Object -Unique)
}

function Get-OfficeDetails {
    $ctr = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue
    if (-not $ctr) { $ctr = Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\ClickToRun\Configuration' -ErrorAction SilentlyContinue }
    if ($ctr) {
        return [pscustomobject]@{
            Product = if ($ctr.ProductReleaseIds) { [string]$ctr.ProductReleaseIds } else { "Office Click-to-Run" }
            Version = if ($ctr.VersionToReport) { [string]$ctr.VersionToReport } else { Get-LocalLicenseText "localLicense.unknown" }
            Platform = if ($ctr.Platform) { [string]$ctr.Platform } else { Get-LocalLicenseText "localLicense.unknown" }
        }
    }
    return [pscustomobject]@{ Product=(Get-LocalLicenseText "localLicense.office.notDetected"); Version=""; Platform="" }
}

function ConvertTo-LocalLicenseStateCode {
    param([AllowNull()][object]$LicenseStatus)
    if ($null -eq $LicenseStatus) { return 'Unknown' }
    switch ([int]$LicenseStatus) {
        1 { return 'Licensed' }
        2 { return 'Grace' }
        3 { return 'Grace' }
        4 { return 'NonGenuineGrace' }
        5 { return 'Notification' }
        6 { return 'Grace' }
        default { return 'Unlicensed' }
    }
}

function Get-LocalLicenseStateLabel {
    param([AllowNull()][string]$StateCode)
    switch ([string]$StateCode) {
        'Licensed' { return Get-LocalLicenseText 'localLicense.state.licensed' }
        'Notification' { return Get-LocalLicenseText 'localLicense.state.notification' }
        'Grace' { return Get-LocalLicenseText 'localLicense.state.grace' }
        'NonGenuineGrace' { return Get-LocalLicenseText 'localLicense.state.nonGenuineGrace' }
        'Unlicensed' { return Get-LocalLicenseText 'localLicense.state.unlicensed' }
        'NotDetected' { return Get-LocalLicenseText 'localLicense.state.notDetected' }
        default { return Get-LocalLicenseText 'localLicense.state.unknown' }
    }
}

function Get-WindowsActivationState {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$ExpectedLast5 = '',
        [scriptblock]$LicenseQuery
    )

    try {
        $licenses = if ($LicenseQuery) {
            @(& $LicenseQuery)
        } elseif (Get-Command Get-CimInstance -ErrorAction SilentlyContinue) {
            @(Get-CimInstance -ClassName SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Stop)
        } else {
            @(Get-WmiObject -Class SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f'" -ErrorAction Stop)
        }
        $windowsLicenses = @($licenses | Where-Object {
            [string]$_.Name -match '(?i)^Windows' -and
            ($_.PSObject.Properties['LicenseStatus'] -or $_.PSObject.Properties['PartialProductKey'])
        })
        $primary = $windowsLicenses | Sort-Object `
            @{Expression={ if ([int]$_.LicenseStatus -eq 1) { 0 } elseif (-not [string]::IsNullOrWhiteSpace([string]$_.PartialProductKey)) { 1 } else { 2 } }}, `
            @{Expression={ [int]$_.LicenseStatus }; Descending=$true} | Select-Object -First 1
        if (-not $primary) {
            return [pscustomobject][ordered]@{
                ProbeSucceeded=$true; ActivationConfirmed=$false; RequestedKeyActivationConfirmed=$false
                StateCode='Unlicensed'; LicenseStatus=0; ProductName=''; ProductKeyLast5=''; Error=''
            }
        }
        $stateCode = ConvertTo-LocalLicenseStateCode $primary.LicenseStatus
        $last5 = ([string]$primary.PartialProductKey).Trim().ToUpperInvariant()
        $activated = [bool]([int]$primary.LicenseStatus -eq 1)
        $requestedConfirmed = [bool]($activated -and (
            [string]::IsNullOrWhiteSpace($ExpectedLast5) -or
            [string]::Equals($last5, $ExpectedLast5.Trim().ToUpperInvariant(), [StringComparison]::OrdinalIgnoreCase)
        ))
        return [pscustomobject][ordered]@{
            ProbeSucceeded=$true; ActivationConfirmed=$activated; RequestedKeyActivationConfirmed=$requestedConfirmed
            StateCode=$stateCode; LicenseStatus=[int]$primary.LicenseStatus; ProductName=[string]$primary.Name
            ProductKeyLast5=$last5; Error=''
        }
    } catch {
        return [pscustomobject][ordered]@{
            ProbeSucceeded=$false; ActivationConfirmed=$false; RequestedKeyActivationConfirmed=$false
            StateCode='Unknown'; LicenseStatus=-1; ProductName=''; ProductKeyLast5=''; Error=[string]$_.Exception.Message
        }
    }
}

function Get-OfficeLicenseRecordsFromStatus {
    param([AllowNull()][string]$StatusText)

    if ([string]::IsNullOrWhiteSpace($StatusText)) { return @() }
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($block in @([regex]::Split($StatusText, '(?m)^\s*-{10,}\s*$'))) {
        $statusMatch = [regex]::Match($block, '(?im)^\s*LICENSE STATUS\s*:\s*(?<Value>[^\r\n]+)')
        if (-not $statusMatch.Success) { continue }
        $last5Match = [regex]::Match($block, '(?im)^\s*Last 5 characters of installed product key\s*:\s*(?<Value>[A-Z0-9]{5})\s*$')
        $nameMatch = [regex]::Match($block, '(?im)^\s*LICENSE NAME\s*:\s*(?<Value>[^\r\n]+)')
        $statusValue = $statusMatch.Groups['Value'].Value.Trim()
        $records.Add([pscustomobject][ordered]@{
            Name=$(if ($nameMatch.Success) { $nameMatch.Groups['Value'].Value.Trim() } else { '' })
            Status=$statusValue
            ProductKeyLast5=$(if ($last5Match.Success) { $last5Match.Groups['Value'].Value.Trim().ToUpperInvariant() } else { '' })
            ActivationConfirmed=[bool]($statusValue -match '(?i)---LICENSED---')
        })
    }
    return $records.ToArray()
}

function Get-OfficeActivationState {
    [CmdletBinding()]
    param(
        [AllowNull()][string[]]$OsppPaths,
        [AllowEmptyString()][string]$ExpectedLast5 = '',
        [scriptblock]$StatusInvoker
    )

    $paths = @($OsppPaths | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
    if ($paths.Count -eq 0) {
        return [pscustomobject][ordered]@{
            ProbeSucceeded=$false; ActivationConfirmed=$false; RequestedKeyActivationConfirmed=$false
            StateCode='NotDetected'; ProductName=''; ProductKeyLast5=''; RecordCount=0; Error='OSPP.VBS not found'
        }
    }
    $allRecords = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $probeSucceeded = $false
    foreach ($path in $paths) {
        try {
            $result = if ($StatusInvoker) {
                & $StatusInvoker $path
            } else {
                Invoke-CapturedProcess -FilePath $nativeCscriptPath -Arguments ('//nologo "{0}" /dstatusall' -f $path)
            }
            if ($null -eq $result) { throw 'Office status probe returned no result.' }
            $probeSucceeded = [bool]($probeSucceeded -or [int]$result.ExitCode -eq 0)
            foreach ($record in @(Get-OfficeLicenseRecordsFromStatus -StatusText ([string]$result.Output))) { $allRecords.Add($record) }
            if ([int]$result.ExitCode -ne 0) { $errors.Add("$path (exit $([int]$result.ExitCode))") }
        } catch {
            $errors.Add("$path ($($_.Exception.Message))")
        }
    }
    $licensedRecords = @($allRecords.ToArray() | Where-Object { [bool]$_.ActivationConfirmed })
    $expected = $ExpectedLast5.Trim().ToUpperInvariant()
    $matchingLicensedRecords = @(if ([string]::IsNullOrWhiteSpace($expected)) {
        @($licensedRecords)
    } else {
        @($licensedRecords | Where-Object { [string]::Equals([string]$_.ProductKeyLast5, $expected, [StringComparison]::OrdinalIgnoreCase) })
    })
    $selected = @($matchingLicensedRecords | Select-Object -First 1)
    if ($selected.Count -eq 0) { $selected = @($licensedRecords | Select-Object -First 1) }
    $activationConfirmed = [bool]($licensedRecords.Count -gt 0)
    return [pscustomobject][ordered]@{
        ProbeSucceeded=[bool]$probeSucceeded
        ActivationConfirmed=$activationConfirmed
        RequestedKeyActivationConfirmed=[bool]($activationConfirmed -and $matchingLicensedRecords.Count -gt 0)
        StateCode=$(if ($activationConfirmed) { 'Licensed' } elseif ($allRecords.Count -gt 0) { 'Unlicensed' } else { 'Unknown' })
        ProductName=$(if ($selected.Count -gt 0) { [string]$selected[0].Name } else { '' })
        ProductKeyLast5=$(if ($selected.Count -gt 0) { [string]$selected[0].ProductKeyLast5 } else { '' })
        RecordCount=[int]$allRecords.Count
        Error=($errors.ToArray() -join '; ')
    }
}

function Test-LocalLicenseActivationConfirmed {
    param([AllowNull()][object]$State)
    return [bool]($null -ne $State -and $State.PSObject.Properties['RequestedKeyActivationConfirmed'] -and [bool]$State.RequestedKeyActivationConfirmed)
}

function Wait-LocalLicensePostCheck {
    param(
        [Parameter(Mandatory=$true)][scriptblock]$Probe,
        [ValidateRange(1,10)][int]$Attempts = 3,
        [ValidateRange(0,10000)][int]$DelayMilliseconds = 1200
    )
    $lastState = $null
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        $lastState = & $Probe
        if (Test-LocalLicenseActivationConfirmed -State $lastState) { return $lastState }
        if ($attempt -lt $Attempts -and $DelayMilliseconds -gt 0) { Start-Sleep -Milliseconds $DelayMilliseconds }
    }
    return $lastState
}

function Get-WindowsActivationStatusText {
    param([AllowNull()][object]$State)
    if ($State -and [bool]$State.ActivationConfirmed) {
        return Get-LocalLicenseText 'localLicense.windows.status.activated'
    }
    if ($State -and [bool]$State.ProbeSucceeded) {
        return Get-LocalLicenseText 'localLicense.windows.status.notActivated' @((Get-LocalLicenseStateLabel ([string]$State.StateCode)))
    }
    return Get-LocalLicenseText 'localLicense.windows.status.unknown'
}

function Get-OfficeActivationStatusText {
    param([AllowNull()][object]$State)
    if ($State -and [bool]$State.ActivationConfirmed) {
        return Get-LocalLicenseText 'localLicense.office.status.activated'
    }
    if ($State -and [string]$State.StateCode -eq 'Unlicensed') {
        return Get-LocalLicenseText 'localLicense.office.status.notActivated'
    }
    return Get-LocalLicenseText 'localLicense.office.status.unknown'
}

$localTypography = Get-ToolUiTypography
$font = New-Object System.Drawing.Font($localTypography.FontFamily, $localTypography.NormalSize)
$fontBold = New-Object System.Drawing.Font($localTypography.FontFamily, $localTypography.NormalSize, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font($localTypography.FontFamily, $localTypography.DialogTitleSize, [System.Drawing.FontStyle]::Bold)

$form = New-Object System.Windows.Forms.Form
$form.Text = Get-LocalLicenseText "localLicense.form.title" @($script:localLicenseVersion)
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(720, 520)
$form.MinimumSize = New-Object System.Drawing.Size(680, 490)
$form.BackColor = [System.Drawing.Color]::FromArgb(244, 246, 249)
$form.Font = $font
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::Dpi

$header = New-Object System.Windows.Forms.Panel
$header.Dock = 'Top'
$header.Height = 65
$form.Controls.Add($header)

$title = New-Object System.Windows.Forms.Label
$title.Text = Get-LocalLicenseText "localLicense.title"
$title.Font = $fontTitle
$title.ForeColor = [System.Drawing.Color]::FromArgb(18, 59, 116)
$title.TextAlign = 'MiddleCenter'
$title.Dock = 'Top'
$title.Height = 36
$header.Controls.Add($title)

$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = if ($script:localOfflineMode) {
    Get-LocalLicenseText "localLicense.subtitle.offline"
} else {
    Get-LocalLicenseText "localLicense.subtitle.ready"
}
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(90, 98, 112)
$subtitle.TextAlign = 'MiddleCenter'
$subtitle.Dock = 'Bottom'
$subtitle.Height = 27
$header.Controls.Add($subtitle)

$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock = 'Bottom'
$bottom.Height = 48
$form.Controls.Add($bottom)

$close = New-Object System.Windows.Forms.Button
$close.Text = Get-LocalLicenseText "localLicense.close"
$close.Font = $fontBold
$close.Size = New-Object System.Drawing.Size(104, 30)
$close.Location = New-Object System.Drawing.Point(600, 8)
$close.Anchor = 'Top,Right'
$close.Add_Click({ $form.Close() })
$bottom.Controls.Add($close)

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Dock = 'Fill'
$form.Controls.Add($tabs)
$tabs.BringToFront()

$windowsTab = New-Object System.Windows.Forms.TabPage
$windowsTab.Text = 'Windows'
$windowsTab.BackColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($windowsTab)

$officeTab = New-Object System.Windows.Forms.TabPage
$officeTab.Text = 'Microsoft Office'
$officeTab.BackColor = [System.Drawing.Color]::White
$tabs.TabPages.Add($officeTab)

$windowsInfo = Get-WindowsDetails
$windowsTargets = @(Get-WindowsTargetEditions)
$windowsActivationState = if ([string]$env:TOOL_UI_SMOKE_TEST -eq '1') {
    [pscustomobject]@{ ProbeSucceeded=$true; ActivationConfirmed=$false; RequestedKeyActivationConfirmed=$false; StateCode='Notification'; ProductKeyLast5=''; Error='' }
} else {
    Get-WindowsActivationState
}

$winCurrent = New-Object System.Windows.Forms.Label
$winCurrent.Location = New-Object System.Drawing.Point(18, 16)
$winCurrent.Size = New-Object System.Drawing.Size(660, 42)
$winCurrent.Anchor = 'Top,Left,Right'
$winCurrent.Font = $fontBold
$winCurrent.Text = Get-LocalLicenseText "localLicense.current" @("$($windowsInfo.Name) | Edition: $($windowsInfo.Edition) | $($windowsInfo.Release) build $($windowsInfo.Build)")
$windowsTab.Controls.Add($winCurrent)

$winActivationStatus = New-Object System.Windows.Forms.Label
$winActivationStatus.Location = New-Object System.Drawing.Point(18, 55)
$winActivationStatus.Size = New-Object System.Drawing.Size(660, 42)
$winActivationStatus.Anchor = 'Top,Left,Right'
$winActivationStatus.ForeColor = if ([bool]$windowsActivationState.ActivationConfirmed) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$winActivationStatus.Text = Get-WindowsActivationStatusText -State $windowsActivationState
$windowsTab.Controls.Add($winActivationStatus)

$winTargetLabel = New-Object System.Windows.Forms.Label
$winTargetLabel.Location = New-Object System.Drawing.Point(18, 103)
$winTargetLabel.Size = New-Object System.Drawing.Size(660, 22)
$winTargetLabel.Text = Get-LocalLicenseText "localLicense.windows.targets"
$windowsTab.Controls.Add($winTargetLabel)

$winTarget = New-Object System.Windows.Forms.ComboBox
$winTarget.DropDownStyle = 'DropDownList'
$winTarget.Location = New-Object System.Drawing.Point(18, 127)
$winTarget.Size = New-Object System.Drawing.Size(330, 28)
[void]$winTarget.Items.Add((Get-LocalLicenseText "localLicense.windows.keepEdition"))
foreach ($target in $windowsTargets) { [void]$winTarget.Items.Add($target) }
$winTarget.SelectedIndex = 0
$windowsTab.Controls.Add($winTarget)

$winKeyLabel = New-Object System.Windows.Forms.Label
$winKeyLabel.Location = New-Object System.Drawing.Point(18, 166)
$winKeyLabel.Size = New-Object System.Drawing.Size(660, 22)
$winKeyLabel.Text = Get-LocalLicenseText "localLicense.windows.keyLabel"
$windowsTab.Controls.Add($winKeyLabel)

$winKey = New-Object System.Windows.Forms.TextBox
$winKey.Location = New-Object System.Drawing.Point(18, 190)
$winKey.Size = New-Object System.Drawing.Size(330, 26)
$winKey.UseSystemPasswordChar = $true
$winKey.CharacterCasing = 'Upper'
$winKey.MaxLength = 29
$windowsTab.Controls.Add($winKey)

$winApply = New-Object System.Windows.Forms.Button
$winApply.Text = Get-LocalLicenseText "localLicense.windows.apply"
$winApply.Font = $fontBold
$winApply.Location = New-Object System.Drawing.Point(365, 187)
$winApply.Size = New-Object System.Drawing.Size(220, 31)
$windowsTab.Controls.Add($winApply)

$winActivation = New-Object System.Windows.Forms.Button
$winActivation.Text = Get-LocalLicenseText "localLicense.windows.activation"
$winActivation.Location = New-Object System.Drawing.Point(18, 231)
$winActivation.Size = New-Object System.Drawing.Size(230, 30)
$winActivation.Add_Click({ Start-Process 'ms-settings:activation' })
$windowsTab.Controls.Add($winActivation)

$winStore = New-Object System.Windows.Forms.Button
$winStore.Text = Get-LocalLicenseText "localLicense.windows.store"
$winStore.Location = New-Object System.Drawing.Point(258, 231)
$winStore.Size = New-Object System.Drawing.Size(290, 30)
$winStore.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked "Microsoft Store"; return }
    Start-Process 'ms-windows-store://windowsupgrade/'
})
$windowsTab.Controls.Add($winStore)

$winResult = New-Object System.Windows.Forms.Label
$winResult.Location = New-Object System.Drawing.Point(18, 271)
$winResult.Size = New-Object System.Drawing.Size(660, 86)
$winResult.Anchor = 'Top,Left,Right'
$winResult.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$winResult.Text = if ($windowsTargets.Count -gt 0) {
    Get-LocalLicenseText "localLicense.windows.targetsFound" @(($windowsTargets -join ', '))
} else {
    Get-LocalLicenseText "localLicense.windows.targetsMissing"
}
$windowsTab.Controls.Add($winResult)

$winApply.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked (Get-LocalLicenseText "localLicense.windows.apply"); return }
    $key = Normalize-ProductKey $winKey.Text
    $winKey.Clear()
    if (-not (Test-ProductKeyFormat $key)) {
        [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.error.invalidKey"), (Get-LocalLicenseText "localLicense.error.invalidKeyTitle"), 'OK', 'Warning') | Out-Null
        return
    }
    $selectedTarget = [string]$winTarget.SelectedItem
    $masked = Mask-ProductKey $key
    $message = Get-LocalLicenseText "localLicense.windows.confirm" @($windowsInfo.Edition, $selectedTarget, $masked)
    $answer = [System.Windows.Forms.MessageBox]::Show($message, (Get-LocalLicenseText "localLicense.windows.confirmTitle"), 'YesNo', 'Warning')
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { $key = $null; return }
    try {
        $form.UseWaitCursor = $true
        $winApply.Enabled = $false
        $winResult.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
        $winResult.Text = Get-LocalLicenseText "localLicense.windows.applying"
        [System.Windows.Forms.Application]::DoEvents()
        $process = Start-Process -FilePath (Get-ToolNativeSystemPath "changepk.exe") -ArgumentList "/ProductKey $key" -Wait -PassThru
        if ($process.ExitCode -eq 0) {
            $expectedLast5 = $key.Substring($key.Length - 5)
            $postCheck = Wait-LocalLicensePostCheck -Probe { Get-WindowsActivationState -ExpectedLast5 $expectedLast5 }
            $winActivationStatus.Text = Get-WindowsActivationStatusText -State $postCheck
            if (Test-LocalLicenseActivationConfirmed -State $postCheck) {
                $winActivationStatus.ForeColor = [System.Drawing.Color]::DarkGreen
                $winResult.ForeColor = [System.Drawing.Color]::DarkGreen
                $winResult.Text = Get-LocalLicenseText "localLicense.windows.activationConfirmed" @($masked)
                [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.windows.activationConfirmedMessage"), (Get-LocalLicenseText "localLicense.windows.activationConfirmedTitle"), 'OK', 'Information') | Out-Null
            } else {
                $winActivationStatus.ForeColor = [System.Drawing.Color]::DarkOrange
                $winResult.ForeColor = [System.Drawing.Color]::DarkOrange
                $winResult.Text = Get-LocalLicenseText "localLicense.windows.activationPending" @($masked, (Get-LocalLicenseStateLabel ([string]$postCheck.StateCode)))
                try { Start-Process 'ms-settings:activation' } catch {}
            }
        } else {
            $winResult.ForeColor = [System.Drawing.Color]::DarkRed
            $winResult.Text = Get-LocalLicenseText "localLicense.windows.rejected" @($process.ExitCode)
        }
    } catch {
        $winResult.ForeColor = [System.Drawing.Color]::DarkRed
        $winResult.Text = Get-LocalLicenseText "localLicense.windows.failed" @($_.Exception.Message)
    } finally {
        $key = $null
        $winApply.Enabled = -not $script:localOfflineMode
        $form.UseWaitCursor = $false
    }
})

$officeDetails = Get-OfficeDetails
$osppPaths = @(Get-OfficeOsppPaths)
$officeActivationState = if ([string]$env:TOOL_UI_SMOKE_TEST -eq '1') {
    [pscustomobject]@{ ProbeSucceeded=$true; ActivationConfirmed=$false; RequestedKeyActivationConfirmed=$false; StateCode='Unlicensed'; ProductKeyLast5=''; Error='' }
} else {
    Get-OfficeActivationState -OsppPaths $osppPaths
}

$officeCurrent = New-Object System.Windows.Forms.Label
$officeCurrent.Location = New-Object System.Drawing.Point(18, 16)
$officeCurrent.Size = New-Object System.Drawing.Size(660, 42)
$officeCurrent.Anchor = 'Top,Left,Right'
$officeCurrent.Font = $fontBold
$officeCurrent.Text = Get-LocalLicenseText "localLicense.current" @("$($officeDetails.Product) | $($script:officeCompatibility.Family) | $(Get-LocalLicenseText "localLicense.build"): $($officeDetails.Version) | $($script:officeCompatibility.Channel)")
$officeTab.Controls.Add($officeCurrent)

$officeActivationStatus = New-Object System.Windows.Forms.Label
$officeActivationStatus.Location = New-Object System.Drawing.Point(18, 55)
$officeActivationStatus.Size = New-Object System.Drawing.Size(660, 42)
$officeActivationStatus.Anchor = 'Top,Left,Right'
$officeActivationStatus.ForeColor = if ([bool]$officeActivationState.ActivationConfirmed) { [System.Drawing.Color]::DarkGreen } else { [System.Drawing.Color]::DarkOrange }
$officeActivationStatus.Text = Get-OfficeActivationStatusText -State $officeActivationState
$officeTab.Controls.Add($officeActivationStatus)

$officeKeyLabel = New-Object System.Windows.Forms.Label
$officeKeyLabel.Location = New-Object System.Drawing.Point(18, 105)
$officeKeyLabel.Size = New-Object System.Drawing.Size(660, 22)
$officeKeyLabel.Text = Get-LocalLicenseText "localLicense.office.keyLabel"
$officeTab.Controls.Add($officeKeyLabel)

$officeKey = New-Object System.Windows.Forms.TextBox
$officeKey.Location = New-Object System.Drawing.Point(18, 129)
$officeKey.Size = New-Object System.Drawing.Size(330, 26)
$officeKey.UseSystemPasswordChar = $true
$officeKey.CharacterCasing = 'Upper'
$officeKey.MaxLength = 29
$officeTab.Controls.Add($officeKey)

$officeApply = New-Object System.Windows.Forms.Button
$officeApply.Text = Get-LocalLicenseText "localLicense.office.apply"
$officeApply.Font = $fontBold
$officeApply.Location = New-Object System.Drawing.Point(365, 126)
$officeApply.Size = New-Object System.Drawing.Size(220, 31)
$officeApply.Enabled = ($osppPaths.Count -gt 0)
$officeTab.Controls.Add($officeApply)

$officeSwitch = New-Object System.Windows.Forms.Button
$officeSwitch.Text = Get-LocalLicenseText "localLicense.office.licenses"
$officeSwitch.Location = New-Object System.Drawing.Point(18, 175)
$officeSwitch.Size = New-Object System.Drawing.Size(260, 30)
$officeSwitch.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked (Get-LocalLicenseText "localLicense.office.licenses"); return }
    Start-Process 'https://account.microsoft.com/services'
})
$officeTab.Controls.Add($officeSwitch)

$officeRedeem = New-Object System.Windows.Forms.Button
$officeRedeem.Text = Get-LocalLicenseText "localLicense.office.redeem"
$officeRedeem.Location = New-Object System.Drawing.Point(288, 175)
$officeRedeem.Size = New-Object System.Drawing.Size(270, 30)
$officeRedeem.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked (Get-LocalLicenseText "localLicense.office.redeem"); return }
    Start-Process 'https://microsoft365.com/setup'
})
$officeTab.Controls.Add($officeRedeem)

$officeResult = New-Object System.Windows.Forms.Label
$officeResult.Location = New-Object System.Drawing.Point(18, 216)
$officeResult.Size = New-Object System.Drawing.Size(660, 140)
$officeResult.Anchor = 'Top,Left,Right'
$officeResult.ForeColor = [System.Drawing.Color]::FromArgb(52, 64, 84)
$officeResult.Text = if ($osppPaths.Count -gt 0) {
    Get-LocalLicenseText "localLicense.office.osppFound"
} else {
    Get-LocalLicenseText "localLicense.office.osppMissing"
}
$officeTab.Controls.Add($officeResult)

$officeApply.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked (Get-LocalLicenseText "localLicense.office.apply"); return }
    $key = Normalize-ProductKey $officeKey.Text
    $officeKey.Clear()
    if (-not (Test-ProductKeyFormat $key)) {
        [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.error.invalidKey"), (Get-LocalLicenseText "localLicense.error.invalidKeyTitle"), 'OK', 'Warning') | Out-Null
        return
    }
    $ospp = [string]$osppPaths[0]
    $masked = Mask-ProductKey $key
    $answer = [System.Windows.Forms.MessageBox]::Show(
        (Get-LocalLicenseText "localLicense.office.confirm" @($masked)),
        (Get-LocalLicenseText "localLicense.office.confirmTitle"),
        'YesNo',
        'Warning'
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) { $key = $null; return }
    try {
        $form.UseWaitCursor = $true
        $officeApply.Enabled = $false
        $officeResult.Text = Get-LocalLicenseText "localLicense.office.installing"
        [System.Windows.Forms.Application]::DoEvents()
        $install = Invoke-CapturedProcess -FilePath $nativeCscriptPath -Arguments ('//nologo "{0}" /inpkey:{1}' -f $ospp, $key)
        $safeInstallOutput = ([string]$install.Output).Replace($key, $masked)
        if ($install.ExitCode -ne 0 -or $safeInstallOutput -match '(?i)error|0xC[0-9A-F]+') {
            $officeResult.ForeColor = [System.Drawing.Color]::DarkRed
            $officeResult.Text = Get-LocalLicenseText "localLicense.office.rejected" @($masked, $safeInstallOutput)
            return
        }
        $officeResult.Text = Get-LocalLicenseText "localLicense.office.activating"
        [System.Windows.Forms.Application]::DoEvents()
        $activation = Invoke-CapturedProcess -FilePath $nativeCscriptPath -Arguments ('//nologo "{0}" /act' -f $ospp)
        $safeActivationOutput = ([string]$activation.Output).Replace($key, $masked)
        $expectedLast5 = $key.Substring($key.Length - 5)
        $postCheck = Wait-LocalLicensePostCheck -Probe { Get-OfficeActivationState -OsppPaths $osppPaths -ExpectedLast5 $expectedLast5 }
        $officeActivationStatus.Text = Get-OfficeActivationStatusText -State $postCheck
        if (Test-LocalLicenseActivationConfirmed -State $postCheck) {
            $officeActivationStatus.ForeColor = [System.Drawing.Color]::DarkGreen
            $officeResult.ForeColor = [System.Drawing.Color]::DarkGreen
            $officeResult.Text = Get-LocalLicenseText "localLicense.office.activationConfirmed" @($masked)
            [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.office.activationConfirmedMessage"), (Get-LocalLicenseText "localLicense.office.activationConfirmedTitle"), 'OK', 'Information') | Out-Null
        } else {
            $officeActivationStatus.ForeColor = [System.Drawing.Color]::DarkOrange
            $officeResult.ForeColor = [System.Drawing.Color]::DarkOrange
            $officeResult.Text = Get-LocalLicenseText "localLicense.office.activationPending" @($masked, $safeActivationOutput)
        }
    } catch {
        $officeResult.ForeColor = [System.Drawing.Color]::DarkRed
        $officeResult.Text = Get-LocalLicenseText "localLicense.office.failed" @($_.Exception.Message)
    } finally {
        $key = $null
        $officeApply.Enabled = [bool]($osppPaths.Count -gt 0 -and -not $script:localOfflineMode)
        $form.UseWaitCursor = $false
    }
})

Set-ToolWindowTheme -Root $form -Mode $script:localLicenseTheme
$winStore.Enabled = -not $script:localOfflineMode
$officeSwitch.Enabled = -not $script:localOfflineMode
$officeRedeem.Enabled = -not $script:localOfflineMode
$winApply.Enabled = -not $script:localOfflineMode
$officeApply.Enabled = [bool]($osppPaths.Count -gt 0 -and -not $script:localOfflineMode)
if ([string]$env:TOOL_UI_SMOKE_TEST -eq "1") {
    if ($form.Text -ne (Get-LocalLicenseText "localLicense.form.title" @($script:localLicenseVersion))) {
        throw (Get-LocalLicenseText "localLicense.smoke.title")
    }
    if ($title.Text -ne (Get-LocalLicenseText "localLicense.title") -or
        $close.Text -ne (Get-LocalLicenseText "localLicense.close") -or
        $winApply.Text -ne (Get-LocalLicenseText "localLicense.windows.apply") -or
        $officeApply.Text -ne (Get-LocalLicenseText "localLicense.office.apply") -or
        $winActivationStatus.Text -notmatch 'ActivationConfirmed\s*=\s*FALSE' -or
        $officeActivationStatus.Text -notmatch 'ActivationConfirmed\s*=\s*FALSE') {
        throw (Get-LocalLicenseText "localLicense.smoke.controls")
    }
    if ($script:localLicenseCulture -eq "en-US") {
        $visibleText = @(
            $form.Text, $title.Text, $subtitle.Text, $close.Text,
            $winActivationStatus.Text, $officeActivationStatus.Text,
            $winTargetLabel.Text, $winKeyLabel.Text, $winApply.Text,
            $winActivation.Text, $winStore.Text, $officeKeyLabel.Text,
            $officeApply.Text, $officeSwitch.Text, $officeRedeem.Text
        ) -join "`n"
        if ($visibleText -cmatch '[À-ỹ]') { throw (Get-LocalLicenseText "localLicense.smoke.englishLeak" @($visibleText)) }
    }
    $clippedButtons = New-Object System.Collections.Generic.List[string]
    foreach ($localButton in @($close,$winApply,$winActivation,$winStore,$officeApply,$officeSwitch,$officeRedeem)) {
        $requiredButtonWidth = Get-ToolUiButtonRequiredWidth -Button $localButton -HorizontalSafety 8
        if ($localButton.Width -lt $requiredButtonWidth -or (([string]$localButton.Text).Contains('&') -and $localButton.UseMnemonic)) {
            [void]$clippedButtons.Add([string]$localButton.Text)
        }
    }
    if ($clippedButtons.Count -gt 0) {
        throw (Get-LocalLicenseText "localLicense.smoke.buttonClipped" @(($clippedButtons -join ', ')))
    }
    Write-Output (Get-LocalLicenseText "localLicense.smoke.pass" @($script:localLicenseCulture, (-not $script:localOfflineMode)))
    foreach ($resource in @($font, $fontBold, $fontTitle)) { try { $resource.Dispose() } catch {} }
    $form.Dispose()
    exit 0
}
[void]$form.ShowDialog()

