param()

if ($PSVersionTable.PSVersion.Major -lt 3) { exit 10 }

$script:localLicenseVersion = "4.3.0.8"
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

$localTypography = Get-ToolUiTypography
$font = New-Object System.Drawing.Font($localTypography.FontFamily, $localTypography.NormalSize)
$fontBold = New-Object System.Drawing.Font($localTypography.FontFamily, $localTypography.NormalSize, [System.Drawing.FontStyle]::Bold)
$fontTitle = New-Object System.Drawing.Font($localTypography.FontFamily, $localTypography.DialogTitleSize, [System.Drawing.FontStyle]::Bold)

$form = New-Object System.Windows.Forms.Form
$form.Text = Get-LocalLicenseText "localLicense.form.title" @($script:localLicenseVersion)
$form.StartPosition = 'CenterScreen'
$form.ClientSize = New-Object System.Drawing.Size(720, 470)
$form.MinimumSize = New-Object System.Drawing.Size(680, 440)
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

$winCurrent = New-Object System.Windows.Forms.Label
$winCurrent.Location = New-Object System.Drawing.Point(18, 16)
$winCurrent.Size = New-Object System.Drawing.Size(660, 42)
$winCurrent.Anchor = 'Top,Left,Right'
$winCurrent.Font = $fontBold
$winCurrent.Text = Get-LocalLicenseText "localLicense.current" @("$($windowsInfo.Name) | Edition: $($windowsInfo.Edition) | $($windowsInfo.Release) build $($windowsInfo.Build)")
$windowsTab.Controls.Add($winCurrent)

$winTargetLabel = New-Object System.Windows.Forms.Label
$winTargetLabel.Location = New-Object System.Drawing.Point(18, 65)
$winTargetLabel.Size = New-Object System.Drawing.Size(660, 22)
$winTargetLabel.Text = Get-LocalLicenseText "localLicense.windows.targets"
$windowsTab.Controls.Add($winTargetLabel)

$winTarget = New-Object System.Windows.Forms.ComboBox
$winTarget.DropDownStyle = 'DropDownList'
$winTarget.Location = New-Object System.Drawing.Point(18, 89)
$winTarget.Size = New-Object System.Drawing.Size(330, 28)
[void]$winTarget.Items.Add((Get-LocalLicenseText "localLicense.windows.keepEdition"))
foreach ($target in $windowsTargets) { [void]$winTarget.Items.Add($target) }
$winTarget.SelectedIndex = 0
$windowsTab.Controls.Add($winTarget)

$winKeyLabel = New-Object System.Windows.Forms.Label
$winKeyLabel.Location = New-Object System.Drawing.Point(18, 130)
$winKeyLabel.Size = New-Object System.Drawing.Size(660, 22)
$winKeyLabel.Text = Get-LocalLicenseText "localLicense.windows.keyLabel"
$windowsTab.Controls.Add($winKeyLabel)

$winKey = New-Object System.Windows.Forms.TextBox
$winKey.Location = New-Object System.Drawing.Point(18, 154)
$winKey.Size = New-Object System.Drawing.Size(330, 26)
$winKey.UseSystemPasswordChar = $true
$winKey.CharacterCasing = 'Upper'
$winKey.MaxLength = 29
$windowsTab.Controls.Add($winKey)

$winApply = New-Object System.Windows.Forms.Button
$winApply.Text = Get-LocalLicenseText "localLicense.windows.apply"
$winApply.Font = $fontBold
$winApply.Location = New-Object System.Drawing.Point(365, 151)
$winApply.Size = New-Object System.Drawing.Size(185, 31)
$windowsTab.Controls.Add($winApply)

$winActivation = New-Object System.Windows.Forms.Button
$winActivation.Text = Get-LocalLicenseText "localLicense.windows.activation"
$winActivation.Location = New-Object System.Drawing.Point(18, 196)
$winActivation.Size = New-Object System.Drawing.Size(210, 30)
$winActivation.Add_Click({ Start-Process 'ms-settings:activation' })
$windowsTab.Controls.Add($winActivation)

$winStore = New-Object System.Windows.Forms.Button
$winStore.Text = Get-LocalLicenseText "localLicense.windows.store"
$winStore.Location = New-Object System.Drawing.Point(238, 196)
$winStore.Size = New-Object System.Drawing.Size(230, 30)
$winStore.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked "Microsoft Store"; return }
    Start-Process 'ms-windows-store://windowsupgrade/'
})
$windowsTab.Controls.Add($winStore)

$winResult = New-Object System.Windows.Forms.Label
$winResult.Location = New-Object System.Drawing.Point(18, 240)
$winResult.Size = New-Object System.Drawing.Size(660, 72)
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
            $winResult.ForeColor = [System.Drawing.Color]::DarkGreen
            $winResult.Text = Get-LocalLicenseText "localLicense.windows.accepted" @($masked)
            [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.windows.acceptedMessage"), (Get-LocalLicenseText "localLicense.windows.acceptedTitle"), 'OK', 'Information') | Out-Null
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

$officeCurrent = New-Object System.Windows.Forms.Label
$officeCurrent.Location = New-Object System.Drawing.Point(18, 16)
$officeCurrent.Size = New-Object System.Drawing.Size(660, 42)
$officeCurrent.Anchor = 'Top,Left,Right'
$officeCurrent.Font = $fontBold
$officeCurrent.Text = Get-LocalLicenseText "localLicense.current" @("$($officeDetails.Product) | $($script:officeCompatibility.Family) | $(Get-LocalLicenseText "localLicense.build"): $($officeDetails.Version) | $($script:officeCompatibility.Channel)")
$officeTab.Controls.Add($officeCurrent)

$officeKeyLabel = New-Object System.Windows.Forms.Label
$officeKeyLabel.Location = New-Object System.Drawing.Point(18, 68)
$officeKeyLabel.Size = New-Object System.Drawing.Size(660, 22)
$officeKeyLabel.Text = Get-LocalLicenseText "localLicense.office.keyLabel"
$officeTab.Controls.Add($officeKeyLabel)

$officeKey = New-Object System.Windows.Forms.TextBox
$officeKey.Location = New-Object System.Drawing.Point(18, 92)
$officeKey.Size = New-Object System.Drawing.Size(330, 26)
$officeKey.UseSystemPasswordChar = $true
$officeKey.CharacterCasing = 'Upper'
$officeKey.MaxLength = 29
$officeTab.Controls.Add($officeKey)

$officeApply = New-Object System.Windows.Forms.Button
$officeApply.Text = Get-LocalLicenseText "localLicense.office.apply"
$officeApply.Font = $fontBold
$officeApply.Location = New-Object System.Drawing.Point(365, 89)
$officeApply.Size = New-Object System.Drawing.Size(185, 31)
$officeApply.Enabled = ($osppPaths.Count -gt 0)
$officeTab.Controls.Add($officeApply)

$officeSwitch = New-Object System.Windows.Forms.Button
$officeSwitch.Text = Get-LocalLicenseText "localLicense.office.licenses"
$officeSwitch.Location = New-Object System.Drawing.Point(18, 138)
$officeSwitch.Size = New-Object System.Drawing.Size(225, 30)
$officeSwitch.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked (Get-LocalLicenseText "localLicense.office.licenses"); return }
    Start-Process 'https://account.microsoft.com/services'
})
$officeTab.Controls.Add($officeSwitch)

$officeRedeem = New-Object System.Windows.Forms.Button
$officeRedeem.Text = Get-LocalLicenseText "localLicense.office.redeem"
$officeRedeem.Location = New-Object System.Drawing.Point(253, 138)
$officeRedeem.Size = New-Object System.Drawing.Size(205, 30)
$officeRedeem.Add_Click({
    if ($script:localOfflineMode) { Show-LocalOfflineBlocked (Get-LocalLicenseText "localLicense.office.redeem"); return }
    Start-Process 'https://microsoft365.com/setup'
})
$officeTab.Controls.Add($officeRedeem)

$officeResult = New-Object System.Windows.Forms.Label
$officeResult.Location = New-Object System.Drawing.Point(18, 183)
$officeResult.Size = New-Object System.Drawing.Size(660, 120)
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
        $safeInstallOutput = $install.Output.Replace($key, $masked)
        if ($install.ExitCode -ne 0 -or $safeInstallOutput -match '(?i)error|0xC[0-9A-F]+') {
            $officeResult.ForeColor = [System.Drawing.Color]::DarkRed
            $officeResult.Text = Get-LocalLicenseText "localLicense.office.rejected" @($masked, $safeInstallOutput)
            return
        }
        $officeResult.Text = Get-LocalLicenseText "localLicense.office.activating"
        [System.Windows.Forms.Application]::DoEvents()
        $activation = Invoke-CapturedProcess -FilePath $nativeCscriptPath -Arguments ('//nologo "{0}" /act' -f $ospp)
        $safeActivationOutput = $activation.Output.Replace($key, $masked)
        if ($activation.ExitCode -eq 0 -and $safeActivationOutput -notmatch '(?i)error|0xC[0-9A-F]+') {
            $officeResult.ForeColor = [System.Drawing.Color]::DarkGreen
            $officeResult.Text = Get-LocalLicenseText "localLicense.office.activated" @($masked)
            [System.Windows.Forms.MessageBox]::Show((Get-LocalLicenseText "localLicense.office.activatedMessage"), (Get-LocalLicenseText "localLicense.office.completedTitle"), 'OK', 'Information') | Out-Null
        } else {
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
        throw "Local license form title is not localized."
    }
    if ($title.Text -ne (Get-LocalLicenseText "localLicense.title") -or
        $close.Text -ne (Get-LocalLicenseText "localLicense.close") -or
        $winApply.Text -ne (Get-LocalLicenseText "localLicense.windows.apply") -or
        $officeApply.Text -ne (Get-LocalLicenseText "localLicense.office.apply")) {
        throw "Local license controls are not synchronized with the selected culture."
    }
    if ($script:localLicenseCulture -eq "en-US") {
        $visibleText = @(
            $form.Text, $title.Text, $subtitle.Text, $close.Text,
            $winTargetLabel.Text, $winKeyLabel.Text, $winApply.Text,
            $winActivation.Text, $winStore.Text, $officeKeyLabel.Text,
            $officeApply.Text, $officeSwitch.Text, $officeRedeem.Text
        ) -join "`n"
        if ($visibleText -cmatch '[À-ỹ]') { throw "English local license UI still contains Vietnamese text:`n$visibleText" }
    }
    Write-Output "LOCAL-LICENSE-UI-SMOKE: PASS (culture=$($script:localLicenseCulture) + Section8NetworkAllowed=$(-not $script:localOfflineMode))"
    foreach ($resource in @($font, $fontBold, $fontTitle)) { try { $resource.Dispose() } catch {} }
    $form.Dispose()
    exit 0
}
[void]$form.ShowDialog()

