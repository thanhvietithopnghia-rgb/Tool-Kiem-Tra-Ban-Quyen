<#
    Trung tâm quản lý license doanh nghiệp của Tool.
    Giao diện chỉ điều phối các thao tác chính; dữ liệu nhạy cảm được xử lý
    trong Tool-Enterprise.ps1 và không ghi product key đầy đủ vào log.
#>
[CmdletBinding()]
param(
    [switch]$SmokeTest
)

$ErrorActionPreference = "Stop"
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$script:enterpriseReleaseVersion = "4.6.0.0"
$script:enterpriseReleaseDisplayName = "v$($script:enterpriseReleaseVersion)"
. (Join-Path $baseDir "Tool-ReportSchema.ps1")
. (Join-Path $baseDir "Tool-Enterprise.ps1")
$localizationHelper = Join-Path $baseDir "Tool-Localization.ps1"
if (-not (Test-Path -LiteralPath $localizationHelper -PathType Leaf)) { throw (Get-ToolEnterpriseText "enterprise.missingComponent" @("Tool-Localization.ps1")) }
. $localizationHelper
$script:enterpriseCulture = Get-ToolCulture
$env:TOOL_UI_CULTURE = $script:enterpriseCulture
$offlinePolicyHelper = Join-Path $baseDir "Tool-OfflinePolicy.ps1"
if (-not (Test-Path -LiteralPath $offlinePolicyHelper -PathType Leaf)) {
    throw (Get-ToolText -Key "enterprise.missingComponent" -Culture $script:enterpriseCulture -FormatArguments @("Tool-OfflinePolicy.ps1"))
}
. $offlinePolicyHelper
$script:enterpriseNetworkAllowed = [bool](Get-ToolEnterpriseNetworkAllowed)
$env:TOOL_ENTERPRISE_NETWORK_ALLOWED = if ($script:enterpriseNetworkAllowed) { "1" } else { "0" }
$uiThemeHelper = Join-Path $baseDir "Tool-UiTheme.ps1"
if (-not (Test-Path -LiteralPath $uiThemeHelper -PathType Leaf)) {
    throw (Get-ToolText -Key "enterprise.missingComponent" -Culture $script:enterpriseCulture -FormatArguments @("Tool-UiTheme.ps1"))
}
. $uiThemeHelper

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

$script:enterpriseTypography = Get-ToolUiTypography
$script:enterpriseFont = New-Object Drawing.Font($script:enterpriseTypography.FontFamily, $script:enterpriseTypography.NormalSize)
$script:enterpriseSmallFont = New-Object Drawing.Font($script:enterpriseTypography.FontFamily, $script:enterpriseTypography.SmallSize)
$script:enterpriseTitleFont = New-Object Drawing.Font($script:enterpriseTypography.FontFamily, $script:enterpriseTypography.DialogTitleSize, [Drawing.FontStyle]::Bold)
$script:enterpriseTheme = Get-ToolUiTheme
$script:baseUiPalette = Get-ToolUiPalette -Mode $script:enterpriseTheme
$script:enterpriseDark = [bool]($script:enterpriseTheme -eq "Dark")
$script:enterprisePalette = @{
    Form             = $script:baseUiPalette.Background
    Surface          = $script:baseUiPalette.Surface
    LocalSurface     = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(48, 40, 28) } else { [Drawing.Color]::FromArgb(255, 251, 235) }
    ServerSurface    = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(28, 39, 58) } else { [Drawing.Color]::FromArgb(239, 246, 255) }
    ClientSurface    = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(26, 47, 45) } else { [Drawing.Color]::FromArgb(240, 253, 250) }
    Header           = $script:baseUiPalette.Primary
    Text             = $script:baseUiPalette.Text
    Muted            = $script:baseUiPalette.Muted
    Success          = $script:baseUiPalette.Success
    Warning          = $script:baseUiPalette.Warning
    DangerText       = $script:baseUiPalette.Danger
    Button           = $script:baseUiPalette.Button
    ButtonHover      = $script:baseUiPalette.ButtonHover
    LocalButton      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(180, 83, 9) } else { [Drawing.Color]::FromArgb(217, 119, 6) }
    LocalHover       = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(146, 64, 14) } else { [Drawing.Color]::FromArgb(180, 83, 9) }
    ServerButton     = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(29, 78, 216) } else { [Drawing.Color]::FromArgb(37, 99, 235) }
    ServerHover      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(30, 64, 175) } else { [Drawing.Color]::FromArgb(29, 78, 216) }
    ClientButton     = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(15, 118, 110) } else { [Drawing.Color]::FromArgb(13, 148, 136) }
    ClientHover      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(17, 94, 89) } else { [Drawing.Color]::FromArgb(15, 118, 110) }
    Navigation      = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(51, 65, 85) } else { [Drawing.Color]::FromArgb(71, 85, 105) }
    NavigationHover = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(39, 49, 65) } else { [Drawing.Color]::FromArgb(51, 65, 85) }
    Danger          = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(153, 27, 27) } else { [Drawing.Color]::FromArgb(185, 28, 28) }
    DangerHover     = if ($script:enterpriseDark) { [Drawing.Color]::FromArgb(127, 29, 29) } else { [Drawing.Color]::FromArgb(153, 27, 27) }
    Input            = $script:baseUiPalette.Input
    Border           = $script:baseUiPalette.Border
}
$script:enterpriseStatus = $null
$script:serverClients = @()
$script:serverProcess = $null
$script:agentProcess = $null
$script:config = $null
$script:serverAddressLabel = $null
$script:enterpriseNetworkButton = $null
$script:previousTabIndex = 0

function Get-EnterpriseText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [object[]]$Arguments = @()
    )
    return Get-ToolText -Key $Key -Culture $script:enterpriseCulture -FormatArguments $Arguments
}

function Set-EnterpriseStatus {
    param([string]$Message, [bool]$Success = $true)
    if ($script:enterpriseStatus) {
        $script:enterpriseStatus.Text = $Message
        $script:enterpriseStatus.ForeColor = if ($Success) { $script:enterprisePalette.Success } else { $script:enterprisePalette.DangerText }
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Show-EnterpriseError {
    param([string]$Message)
    Set-EnterpriseStatus -Message $Message -Success:$false
    [Windows.Forms.MessageBox]::Show(
        $Message,
        (Get-EnterpriseText "enterprise.error.title" @($script:enterpriseReleaseDisplayName)),
        "OK",
        "Error"
    ) | Out-Null
}

function Confirm-EnterpriseAction {
    param(
        [string]$Message,
        [string]$Title = ""
    )
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = Get-EnterpriseText "enterprise.confirm.title" }
    return ([Windows.Forms.MessageBox]::Show($Message, $Title, "YesNo", "Warning") -eq [Windows.Forms.DialogResult]::Yes)
}

function Update-EnterpriseNetworkStateUi {
    param([switch]$UpdateStatus)

    if (-not $script:enterpriseNetworkButton) { return }
    if (-not $script:enterpriseNetworkAllowed) {
        $script:enterpriseNetworkButton.Text = Get-EnterpriseText "enterprise.network.allow"
        Set-EnterpriseButtonStyle $script:enterpriseNetworkButton $script:enterprisePalette.Warning ([Drawing.Color]::White) $script:enterprisePalette.LocalHover
        if ($UpdateStatus) {
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.blockedStatus") $true
        }
    } else {
        $script:enterpriseNetworkButton.Text = Get-EnterpriseText "enterprise.network.disable"
        Set-EnterpriseButtonStyle $script:enterpriseNetworkButton $script:enterprisePalette.Danger ([Drawing.Color]::White) $script:enterprisePalette.DangerHover
        if ($UpdateStatus) {
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.allowedStatus") $true
        }
    }
}

function Enable-EnterpriseNetworkAccess {
    param(
        [string]$Action = "",
        [switch]$SkipConfirmation
    )

    if ($script:enterpriseNetworkAllowed) { return $true }
    if ([string]::IsNullOrWhiteSpace($Action)) { $Action = Get-EnterpriseText "menu.8.title" }
    $message = Get-EnterpriseText "enterprise.network.enablePrompt" @($Action)
    if (-not $SkipConfirmation -and -not (Confirm-EnterpriseAction $message (Get-EnterpriseText "enterprise.network.enableTitle"))) {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.remainsOff") $true
        return $false
    }

    $saved = Set-ToolEnterpriseNetworkAllowedPreference -Allowed $true
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "1"
    $script:enterpriseNetworkAllowed = $true
    Update-EnterpriseNetworkStateUi
    if ($saved) {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.enableSaved") $true
    } else {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.enableSession") $false
    }
    return $true
}

function Disable-EnterpriseNetworkAccess {
    param([switch]$SkipConfirmation)

    if (-not $script:enterpriseNetworkAllowed) { return $true }
    if (-not $SkipConfirmation -and -not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.network.disablePrompt") (Get-EnterpriseText "enterprise.network.disableTitle"))) {
        return $false
    }

    $saved = Set-ToolEnterpriseNetworkAllowedPreference -Allowed $false
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "0"
    $script:enterpriseNetworkAllowed = $false

    try {
        $paths = Get-ToolEnterprisePaths
        if (Test-Path -LiteralPath $paths.ServerConfig -PathType Leaf) {
            New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
        }
    } catch {}
    foreach ($process in @($script:agentProcess, $script:serverProcess)) {
        if ($process -and -not $process.HasExited) {
            try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
        }
    }
    $script:agentProcess = $null
    $script:serverProcess = $null
    Update-EnterpriseNetworkStateUi
    Set-EnterpriseStatus (Get-EnterpriseText $(if ($saved) { "enterprise.network.disableSaved" } else { "enterprise.network.disableSession" })) $saved
    return $true
}

function Toggle-EnterpriseNetworkAccess {
    param([switch]$SkipConfirmation)
    if ($script:enterpriseNetworkAllowed) {
        return Disable-EnterpriseNetworkAccess -SkipConfirmation:$SkipConfirmation
    }
    return Enable-EnterpriseNetworkAccess -SkipConfirmation:$SkipConfirmation
}

function Confirm-EnterpriseNetworkAccess {
    param([string]$ActionKey)
    $action = if ([string]::IsNullOrWhiteSpace($ActionKey)) {
        Get-EnterpriseText "menu.8.title"
    } else {
        Get-EnterpriseText $ActionKey
    }
    return (Enable-EnterpriseNetworkAccess -Action $action)
}

function Get-EnterpriseLauncherPath {
    $candidate = [string]$env:TOOL_LAUNCHER_PATH
    if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
    return ""
}

function Start-EnterpriseChild {
    param([ValidateSet("Server", "Agent")][string]$Role, [bool]$Force = $false)
    Assert-ToolEnterpriseNetworkActionAllowed -Action (Get-EnterpriseText "enterprise.action.childProcess" @($Role))
    $launcher = Get-EnterpriseLauncherPath
    if ($launcher) {
        $arguments = if ($Role -eq "Server") { "--enterprise-server" } elseif ($Force) { "--enterprise-agent-force" } else { "--enterprise-agent" }
        $parameters = @{ FilePath=$launcher; ArgumentList=$arguments; PassThru=$true; WorkingDirectory=$baseDir }
        try { $parameters.Verb = "RunAs" } catch {}
        return (Start-Process @parameters)
    }
    $hostScript = if ($Role -eq "Server") { Join-Path $baseDir "Tool-EnterpriseHost.ps1" } else { Join-Path $baseDir "Tool-EnterpriseAgent.ps1" }
    $ps = if (Get-Command powershell.exe -ErrorAction SilentlyContinue) { (Get-Command powershell.exe).Source } else { "powershell.exe" }
    $fallbackArgs = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$hostScript`""
    if ($Role -eq "Agent" -and $Force) { $fallbackArgs += " -Force" }
    return (Start-Process -FilePath $ps -ArgumentList $fallbackArgs -WorkingDirectory $baseDir -PassThru)
}

function Stop-EnterpriseServer {
    try {
        $paths = Get-ToolEnterprisePaths
        New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.stopRequested") $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900) }
}

function Get-EnterpriseServerConfigurationSafe {
    try { return (Get-ToolEnterpriseServerConfig) } catch { return $null }
}

function Update-EnterpriseDetectedServerAddress {
    $address = ""
    try { $address = [string](Get-ToolEnterprisePreferredServerAddress) } catch {}
    if ($script:serverAddressLabel) {
        if ([string]::IsNullOrWhiteSpace($address)) {
            $script:serverAddressLabel.Text = Get-EnterpriseText "enterprise.server.addressMissing"
            $script:serverAddressLabel.ForeColor = $script:enterprisePalette.DangerText
        } else {
            $script:serverAddressLabel.Text = Get-EnterpriseText "enterprise.server.addressFound" @($address)
            $script:serverAddressLabel.ForeColor = $script:enterprisePalette.Success
        }
    }
    return $address
}

function Find-EnterpriseClientServers {
    param([int]$Port)
    Assert-ToolEnterpriseNetworkActionAllowed -Action (Get-EnterpriseText "enterprise.action.discover")
    $discoveryCidrs = @(Get-ToolEnterpriseLocalDiscoveryCidrs)
    if ($discoveryCidrs.Count -eq 0) { throw (Get-EnterpriseText "enterprise.error.noLan") }
    Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.searching" @(($discoveryCidrs -join ', '))) $true
    return @(Find-ToolEnterpriseLocalServers -Port $Port -TimeoutMs 500 -ThrottleLimit 64)
}

function Resolve-EnterpriseClientServerAddress {
    param([switch]$ForceDiscovery)
    $currentAddress = $script:clientAddressBox.Text.Trim()
    if (-not $ForceDiscovery -and -not [string]::IsNullOrWhiteSpace($currentAddress)) { return $currentAddress }

    $port = [int]$script:clientPortBox.Text
    $servers = @(Find-EnterpriseClientServers -Port $port)
    if ($servers.Count -eq 0) {
        throw (Get-EnterpriseText "enterprise.error.noDiscoveredServer")
    }
    if ($servers.Count -gt 1) {
        $summary = @($servers | ForEach-Object { "$($_.ServerName) [$($_.Address)]" }) -join "; "
        throw (Get-EnterpriseText "enterprise.error.multipleServers" @($summary))
    }
    $address = [string]$servers[0].Address
    $script:clientAddressBox.Text = $address
    Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.discovered" @([string]$servers[0].ServerName, $address, $port)) $true
    return $address
}

function Invoke-ClientDiscover {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.discover")) { return }
        [void](Resolve-EnterpriseClientServerAddress -ForceDiscovery)
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Update-ServerClientList {
    if (-not $script:serverClientList) { return }
    $script:serverClientList.Items.Clear()
    try { $script:serverClients = @(Get-ToolEnterpriseServerClients) } catch { $script:serverClients = @() }
    foreach ($client in $script:serverClients) {
        $item = New-Object Windows.Forms.ListViewItem([string]$client.ComputerName)
        [void]$item.SubItems.Add([string]$client.RemoteAddress)
        [void]$item.SubItems.Add([string]$client.LastSeenUtc)
        [void]$item.SubItems.Add(("{0} / {1}" -f [string]$client.WindowsStatus, [string]$client.OfficeStatus))
        [void]$item.SubItems.Add([string]$client.ClientId)
        $item.Tag = $client
        [void]$script:serverClientList.Items.Add($item)
    }
    $script:clientCountLabel.Text = Get-EnterpriseText "enterprise.server.pairedCount" @($script:serverClients.Count)
}

function Get-SelectedEnterpriseClient {
    if (-not $script:serverClientList -or $script:serverClientList.SelectedItems.Count -eq 0) { return $null }
    return $script:serverClientList.SelectedItems[0].Tag
}

function Test-EnterpriseDuplicateServer {
    param([string[]]$Addresses, [int]$Port)
    $localConfig = Get-EnterpriseServerConfigurationSafe
    $localAddresses = @("127.0.0.1") + @(Get-ToolEnterpriseLocalIPv4Addresses)
    foreach ($address in @($Addresses)) {
        if ([string]::IsNullOrWhiteSpace($address)) { continue }
        $status = Test-ToolEnterpriseServerConnection -ServerAddress $address -Port $Port -TimeoutMs 500
        if ($status -and $localConfig -and $address -notin $localAddresses) {
            return $status
        }
    }
    return $null
}

function Invoke-ServerCreate {
    try {
        $serverName = $script:serverNameBox.Text.Trim()
        $adminCode = $script:serverAdminBox.Text
        $port = [int]$script:serverPortBox.Text
        $cidrs = @($script:serverCidrBox.Lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        if ($adminCode.Length -lt 8) { throw (Get-EnterpriseText "enterprise.error.adminCodeLength") }
        if (Get-EnterpriseServerConfigurationSafe) { throw (Get-EnterpriseText "enterprise.error.serverAlreadyConfigured") }
        $cfg = New-ToolEnterpriseServerConfiguration -ServerName $serverName -AdminCode $adminCode -Port $port -AllowedCidrs $cidrs
        $script:config = $cfg
        $detectedAddress = Update-EnterpriseDetectedServerAddress
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.createdStatus" @($cfg.ServerName, $detectedAddress, $cfg.AuthorityFingerprint)) $true
        [Windows.Forms.MessageBox]::Show(
            (Get-EnterpriseText "enterprise.server.createdMessage"),
            (Get-EnterpriseText "enterprise.server.messageTitle"),
            "OK",
            "Information"
        ) | Out-Null
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Invoke-ServerPairingCode {
    try {
        $adminCode = $script:serverAdminBox.Text
        $code = Get-ToolEnterprisePairingCode -AdminCode $adminCode
        $script:pairingOutputBox.Text = $code
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.pairCreated") $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900) }
}

function Remove-EnterpriseServerNetworkAccess {
    param([ValidateRange(1024, 65535)][int]$Port)

    $warnings = New-Object System.Collections.Generic.List[string]
    $netsh = Join-Path $env:SystemRoot "System32\netsh.exe"
    if (-not (Test-Path -LiteralPath $netsh -PathType Leaf)) {
        [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeNetshMissing"))
        return $warnings.ToArray()
    }

    $url = "http://+:$Port/tool/v1/"
    try {
        $show = & $netsh http show urlacl 2>$null | Out-String
        if ($show -match [regex]::Escape($url)) {
            $process = Start-Process -FilePath $netsh -ArgumentList "http delete urlacl url=$url" -Wait -PassThru -WindowStyle Hidden
            if ($process.ExitCode -ne 0) { [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeUrlExit" @($url, $process.ExitCode))) }
        }
    } catch {
        [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeUrlFailed" @($url)))
    }

    try {
        $firewallArguments = 'advfirewall firewall delete rule name="ThanhViet Tool v4.6 Enterprise Server" protocol=TCP localport=' + $Port
        $process = Start-Process -FilePath $netsh -ArgumentList $firewallArguments -Wait -PassThru -WindowStyle Hidden
        if ($process.ExitCode -ne 0) { [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeFirewallExit" @($Port, $process.ExitCode))) }
    } catch {
        [void]$warnings.Add((Get-EnterpriseText "enterprise.server.revokeFirewallFailed" @($Port)))
    }
    return $warnings.ToArray()
}

function Invoke-ServerDeleteConfiguration {
    try {
        $cfg = Get-EnterpriseServerConfigurationSafe
        if (-not $cfg) { throw (Get-EnterpriseText "enterprise.error.noServerConfiguration") }
        $adminCode = $script:serverAdminBox.Text
        if ([string]::IsNullOrWhiteSpace($adminCode)) { throw (Get-EnterpriseText "enterprise.error.adminCodeRequired") }
        if (-not (Test-ToolEnterpriseAdminCode -AdminCode $adminCode -Verifier $cfg.AdminVerifier)) {
            throw (Get-EnterpriseText "enterprise.error.adminCodeInvalid")
        }

        $message = Get-EnterpriseText "enterprise.server.deletePrompt" @($cfg.ServerName)
        if (-not (Confirm-EnterpriseAction $message)) { return }

        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.deleting") $true
        $result = Remove-ToolEnterpriseServerConfiguration -AdminCode $adminCode -StopTimeoutSeconds 12
        $networkWarnings = @(Remove-EnterpriseServerNetworkAccess -Port ([int]$result.Port))

        $script:config = $null
        $script:serverAdminBox.Clear()
        $script:pairingOutputBox.Clear()
        $script:serverNameBox.Text = [Environment]::MachineName
        $script:serverPortBox.Text = [string]$script:ToolEnterpriseDefaultPort
        $localCidrs = @(Get-ToolEnterpriseLocalCidrs)
        $script:serverCidrBox.Text = ""
        $script:scanInputBox.Text = if ($localCidrs.Count -gt 0) { [string]$localCidrs[0] } else { "" }
        Update-ServerClientList
        [void](Update-EnterpriseDetectedServerAddress)

        $summary = Get-EnterpriseText "enterprise.server.deleted"
        if ($networkWarnings.Count -gt 0) {
            $summary += (Get-EnterpriseText "enterprise.server.warningPrefix") + ($networkWarnings -join " ")
        }
        Set-EnterpriseStatus $summary ($networkWarnings.Count -eq 0)
        [Windows.Forms.MessageBox]::Show(
            $summary + [Environment]::NewLine + [Environment]::NewLine +
            (Get-EnterpriseText "enterprise.server.deletedNext"),
            (Get-EnterpriseText "enterprise.server.deletedTitle"),
            "OK",
            $(if ($networkWarnings.Count -eq 0) { "Information" } else { "Warning" })
        ) | Out-Null
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1200) }
}

function Invoke-ServerStart {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.startServer")) { return }
        $cfg = Get-EnterpriseServerConfigurationSafe
        if (-not $cfg) { throw (Get-EnterpriseText "enterprise.error.createServerFirst") }
        $duplicate = $null
        $localAddresses = @("127.0.0.1") + @(Get-ToolEnterpriseLocalIPv4Addresses)
        foreach ($cidr in @($cfg.AllowedCidrs)) {
            $info = Get-ToolEnterpriseCidrInfo -Cidr ([string]$cidr)
            if ([uint64]$info.HostCount -gt 1024) {
                throw (Get-EnterpriseText "enterprise.error.cidrTooLargeDuplicate" @($info.Cidr))
            }
            foreach ($foundServer in @(Find-ToolEnterpriseServers -Cidr $info.Cidr -Port ([int]$cfg.Port) -TimeoutMs 450 -ThrottleLimit 64)) {
                if ([string]$foundServer.Address -notin $localAddresses) { $duplicate = $foundServer; break }
            }
            if ($duplicate) { break }
        }
        if ($duplicate) {
            throw (Get-EnterpriseText "enterprise.error.duplicateServer" @($duplicate.ServerName, $duplicate.Address))
        }
        if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.server.startPrompt" @($cfg.Port)))) { return }
        $script:serverProcess = Start-EnterpriseChild -Role Server
        $detectedAddress = Update-EnterpriseDetectedServerAddress
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.started" @($detectedAddress, $cfg.Port, $script:serverProcess.Id)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1200) }
}

function Invoke-ServerScan {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.scan")) { return }
        $input = $script:scanInputBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($input)) {
            $scanCandidates = New-Object System.Collections.Generic.List[string]
            $cfg = Get-EnterpriseServerConfigurationSafe
            if ($cfg) {
                foreach ($allowedCidr in @($cfg.AllowedCidrs)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$allowedCidr)) {
                        [void]$scanCandidates.Add([string]$allowedCidr)
                    }
                }
            }
            if ($scanCandidates.Count -eq 0) {
                foreach ($localCidr in @(Get-ToolEnterpriseLocalCidrs)) {
                    if (-not [string]::IsNullOrWhiteSpace([string]$localCidr)) {
                        [void]$scanCandidates.Add([string]$localCidr)
                    }
                }
            }
            if ($scanCandidates.Count -eq 0) { throw (Get-EnterpriseText "enterprise.error.noCidr") }
            $input = [string]$scanCandidates[0]
            $script:scanInputBox.Text = $input
        }
        $cidr = if ($input -match "/") { $input } else { "$input/32" }
        $info = Get-ToolEnterpriseCidrInfo -Cidr $cidr
        if ([uint64]$info.HostCount -gt 1024) { throw (Get-EnterpriseText "enterprise.error.scanTooLarge") }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.scanning" @($info.Cidr)) $true
        $found = @(Find-ToolEnterpriseNetworkDevices -Cidr $cidr -TimeoutMs 250 -ThrottleLimit 64)
        $script:scanResultBox.Clear()
        foreach ($device in $found) {
            $hostLabel = if ($device.HostName) { [string]$device.HostName } else { Get-EnterpriseText "enterprise.server.scanHostUnknown" }
            $line = Get-EnterpriseText "enterprise.server.scanResultLine" @($device.Address, $device.LatencyMs, $hostLabel)
            [void]$script:scanResultBox.AppendText($line + [Environment]::NewLine)
        }
        if ($found.Count -eq 0) { [void]$script:scanResultBox.AppendText((Get-EnterpriseText "enterprise.server.noPing")) }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.scanDone" @($found.Count)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Invoke-ServerExport {
    try {
        $desktopPath = [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
        $result = Export-ToolEnterpriseFleetReport -DestinationDirectory $desktopPath -IncludePdf
        Start-Process -FilePath $result.HtmlPath | Out-Null
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.exported" @($result.ClientCount, $result.JsonPath)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Invoke-ServerJob {
    try {
        $client = Get-SelectedEnterpriseClient
        if (-not $client) { throw (Get-EnterpriseText "enterprise.error.selectClient") }
        $operation = [string]$script:jobOperationBox.SelectedItem
        $key = $script:jobKeyBox.Text.Trim()
        if ($operation -ne "InventoryOnly" -and [string]::IsNullOrWhiteSpace($key)) { throw (Get-EnterpriseText "enterprise.error.keyRequired") }
        if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.server.jobPrompt" @($operation, $client.ComputerName)))) { return }
        $job = New-ToolEnterpriseLicenseJob -ClientId ([string]$client.ClientId) -Operation $operation -ProductKey $key -RequestedBy ([Environment]::UserName)
        $script:jobKeyBox.Clear()
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.jobCreated" @($job.JobId, $job.ProductKeyLast5)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function Invoke-ServerNetworkAccess {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.firewall")) { return }
        $cfg = Get-EnterpriseServerConfigurationSafe
        if (-not $cfg) { throw (Get-EnterpriseText "enterprise.error.noServerConfiguration") }
        if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.server.firewallPrompt" @($cfg.Port)))) { return }
        $netsh = Join-Path $env:SystemRoot "System32\netsh.exe"
        if (-not (Test-Path -LiteralPath $netsh -PathType Leaf)) { throw (Get-EnterpriseText "enterprise.error.netshMissing") }
        $show = & $netsh http show urlacl 2>$null | Out-String
        $url = "http://+:$([int]$cfg.Port)/tool/v1/"
        if ($show -notmatch [regex]::Escape($url)) {
            $aclArgs = "http add urlacl url=$url user=Administrators"
            $aclProcess = Start-Process -FilePath $netsh -ArgumentList $aclArgs -Wait -PassThru -WindowStyle Hidden
            if ($aclProcess.ExitCode -ne 0) { throw (Get-EnterpriseText "enterprise.error.netshExit" @($aclProcess.ExitCode)) }
        }
        if (Get-Command New-NetFirewallRule -ErrorAction SilentlyContinue) {
            try {
                New-NetFirewallRule -DisplayName "ThanhViet Tool v4.6 Enterprise Server" -Direction Inbound -Action Allow -Protocol TCP -LocalPort ([int]$cfg.Port) -Profile Domain,Private -ErrorAction Stop | Out-Null
            } catch {
                # A pre-existing rule is harmless; the URL ACL is the
                # essential listener permission.
            }
        }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.server.firewallReady" @($cfg.Port)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function Invoke-ClientEnroll {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.enroll")) { return }
        $address = Resolve-EnterpriseClientServerAddress
        $port = [int]$script:clientPortBox.Text
        $code = $script:clientPairingBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($code)) { throw (Get-EnterpriseText "enterprise.error.pairingCodeRequired") }
        $cfg = Register-ToolEnterpriseClient -ServerAddress $address -Port $port -PairingCode $code -AllowRemoteLicenseChanges ([bool]$script:clientRemoteChanges.Checked) -AutoSend ([bool]$script:clientAutoSend.Checked)
        $script:clientPairingBox.Clear()
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.enrolled" @($cfg.ClientId, $address, $port)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function Invoke-ClientTest {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.testConnection")) { return }
        $address = Resolve-EnterpriseClientServerAddress
        $status = Test-ToolEnterpriseServerConnection -ServerAddress $address -Port ([int]$script:clientPortBox.Text) -TimeoutMs 1500
        if (-not $status) { throw (Get-EnterpriseText "enterprise.error.connectionFailed") }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.connected" @($address, $status.ProtocolVersion)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900) }
}

function Invoke-ClientSend {
    try {
        if (-not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.sendReport")) { return }
        $script:agentProcess = Start-EnterpriseChild -Role Agent -Force:$true
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.agentStarted" @($script:agentProcess.Id)) $true
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1000) }
}

function Invoke-ClientSchedule {
    param([bool]$Enable)
    try {
        if ($Enable -and -not (Confirm-EnterpriseNetworkAccess -ActionKey "enterprise.action.scheduleAgent")) { return }
        $launcher = Get-EnterpriseLauncherPath
        if (-not $launcher) { throw (Get-EnterpriseText "enterprise.error.oneFileRequired") }
        $taskName = "ThanhViet Tool v4.6 Enterprise Agent"
        if ($Enable) {
            if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.client.enableSchedulePrompt"))) { return }
            $taskRun = "`"$launcher`" --enterprise-agent"
            $arguments = "/Create /TN `"$taskName`" /TR `"$taskRun`" /SC HOURLY /MO 1 /RU SYSTEM /F"
            $p = Start-Process -FilePath (Join-Path $env:SystemRoot "System32\schtasks.exe") -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            if ($p.ExitCode -ne 0) { throw (Get-EnterpriseText "enterprise.error.schtasksExit" @($p.ExitCode)) }
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.scheduleEnabled") $true
        } else {
            if (-not (Confirm-EnterpriseAction (Get-EnterpriseText "enterprise.client.disableSchedulePrompt"))) { return }
            $arguments = "/Delete /TN `"$taskName`" /F"
            $p = Start-Process -FilePath (Join-Path $env:SystemRoot "System32\schtasks.exe") -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
            Set-EnterpriseStatus (Get-EnterpriseText "enterprise.client.scheduleDisabled" @($p.ExitCode)) $true
        }
    } catch { Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1100) }
}

function New-EnterpriseLabel {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 180, [int]$H = 24)
    $label = New-Object Windows.Forms.Label
    $label.Text = $Text
    $label.Location = New-Object Drawing.Point($X, $Y)
    $label.Size = New-Object Drawing.Size($W, $H)
    $label.Font = $script:enterpriseFont
    $label.ForeColor = $script:enterprisePalette.Text
    $label.BackColor = [Drawing.Color]::Transparent
    return $label
}

function New-EnterpriseTextBox {
    param([int]$X, [int]$Y, [int]$W = 260, [int]$H = 25, [bool]$MultiLine = $false, [bool]$Password = $false)
    $box = New-Object Windows.Forms.TextBox
    $box.Location = New-Object Drawing.Point($X, $Y)
    $box.Size = New-Object Drawing.Size($W, $H)
    $box.Font = $script:enterpriseFont
    $box.BackColor = $script:enterprisePalette.Input
    $box.ForeColor = $script:enterprisePalette.Text
    $box.BorderStyle = [Windows.Forms.BorderStyle]::FixedSingle
    $box.Multiline = $MultiLine
    if ($MultiLine) { $box.ScrollBars = "Vertical" }
    if ($Password) { $box.UseSystemPasswordChar = $true }
    return $box
}

function New-EnterpriseButton {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 150, [int]$H = 32, [scriptblock]$Action)
    $button = New-Object Windows.Forms.Button
    $button.Text = $Text
    $button.Location = New-Object Drawing.Point($X, $Y)
    $button.Size = New-Object Drawing.Size($W, $H)
    $button.Font = $script:enterpriseFont
    $button.FlatStyle = "Flat"
    $button.UseVisualStyleBackColor = $false
    $button.BackColor = $script:enterprisePalette.Button
    $button.ForeColor = $script:enterprisePalette.Header
    $button.FlatAppearance.BorderColor = $script:enterprisePalette.Border
    $button.FlatAppearance.BorderSize = 1
    $button.FlatAppearance.MouseOverBackColor = $script:enterprisePalette.ButtonHover
    $button.Cursor = [Windows.Forms.Cursors]::Hand
    if ($Action) { $button.Add_Click($Action) }
    Set-ToolUiActionButtonVisual -Button $button -Mode $script:enterpriseTheme -PreserveColors
    return $button
}

function Set-EnterpriseButtonStyle {
    param(
        [Parameter(Mandatory = $true)]$Button,
        [Parameter(Mandatory = $true)][Drawing.Color]$BackColor,
        [Drawing.Color]$ForeColor = [Drawing.Color]::White,
        [Drawing.Color]$HoverColor = [Drawing.Color]::Empty,
        [Drawing.Color]$BorderColor = [Drawing.Color]::Empty
    )
    if (-not $Button) { return }
    $Button.UseVisualStyleBackColor = $false
    $Button.BackColor = $BackColor
    $Button.ForeColor = $ForeColor
    if ($BorderColor.IsEmpty) { $BorderColor = $BackColor }
    if ($HoverColor.IsEmpty) { $HoverColor = $BackColor }
    $Button.FlatAppearance.BorderColor = $BorderColor
    $Button.FlatAppearance.MouseOverBackColor = $HoverColor
    $Button.FlatAppearance.MouseDownBackColor = $HoverColor
}

function Invoke-EnterpriseBack {
    if ($tabs -and $tabs.SelectedIndex -gt 0) {
        $script:previousTabIndex = $tabs.SelectedIndex
        $tabs.SelectedIndex = $tabs.SelectedIndex - 1
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.navigation.backStatus") $true
    } elseif ($form) {
        # Đóng trung tâm để quay lại cửa sổ/phiên làm việc đã mở mục 8.
        $form.Close()
    }
}

function Invoke-EnterpriseClose {
    if ($form) { $form.Close() }
}

function Find-EnterpriseDirectControl {
    param(
        [Parameter(Mandatory = $true)][Windows.Forms.Control]$Parent,
        [Parameter(Mandatory = $true)][string]$Text
    )
    foreach ($control in $Parent.Controls) {
        if ([string]$control.Text -eq $Text) { return $control }
    }
    return $null
}

function Set-EnterpriseBounds {
    param(
        [Windows.Forms.Control]$Control,
        [int]$X,
        [int]$Y,
        [int]$Width,
        [int]$Height
    )
    if (-not $Control) { return }
    $safeWidth = [Math]::Max(1, $Width)
    $safeHeight = [Math]::Max(1, $Height)
    $Control.SetBounds($X, $Y, $safeWidth, $safeHeight)
}

function Set-EnterpriseAdaptiveButtonRows {
    param(
        [object[]]$Buttons,
        [int]$X,
        [int]$Y,
        [int]$AvailableWidth,
        [int]$Height,
        [int]$Gap = 8,
        [int]$RowGap = 5
    )

    $activeButtons = @($Buttons | Where-Object { $null -ne $_ })
    if ($activeButtons.Count -eq 0) { return 0 }
    $requiredWidths = @($activeButtons | ForEach-Object {
        [Math]::Max(92, (Get-ToolUiButtonRequiredWidth -Button $_))
    })
    $oneRowWidth = [int](($requiredWidths | Measure-Object -Sum).Sum + (($activeButtons.Count - 1) * $Gap))
    $columnCount = if ($oneRowWidth -le $AvailableWidth) { $activeButtons.Count } else { [Math]::Ceiling($activeButtons.Count / 2.0) }
    $rowCount = [int][Math]::Ceiling($activeButtons.Count / [double]$columnCount)

    for ($rowIndex = 0; $rowIndex -lt $rowCount; $rowIndex++) {
        $startIndex = $rowIndex * $columnCount
        $endIndex = [Math]::Min($activeButtons.Count - 1, $startIndex + $columnCount - 1)
        $rowButtons = @($activeButtons[$startIndex..$endIndex])
        $rowRequired = @($requiredWidths[$startIndex..$endIndex])
        $rowGapWidth = ($rowButtons.Count - 1) * $Gap
        $rowMinimumWidth = [int](($rowRequired | Measure-Object -Sum).Sum + $rowGapWidth)
        $extraPerButton = if ($rowMinimumWidth -lt $AvailableWidth) { [Math]::Floor(($AvailableWidth - $rowMinimumWidth) / $rowButtons.Count) } else { 0 }
        $rowX = $X
        for ($columnIndex = 0; $columnIndex -lt $rowButtons.Count; $columnIndex++) {
            $buttonWidth = if ($rowMinimumWidth -le $AvailableWidth) {
                [int]$rowRequired[$columnIndex] + $extraPerButton
            } else {
                [Math]::Floor(($AvailableWidth - $rowGapWidth) / $rowButtons.Count)
            }
            if ($columnIndex -eq ($rowButtons.Count - 1)) {
                $buttonWidth = $X + $AvailableWidth - $rowX
            }
            Set-EnterpriseBounds $rowButtons[$columnIndex] $rowX ($Y + ($rowIndex * ($Height + $RowGap))) $buttonWidth $Height
            $rowX += $buttonWidth + $Gap
        }
    }
    return $rowCount
}

function Get-EnterpriseClippedButtonLabels {
    param([Parameter(Mandatory = $true)][Windows.Forms.Control]$Root)

    foreach ($control in $Root.Controls) {
        if ($control -is [Windows.Forms.Button]) {
            $requiredWidth = Get-ToolUiButtonRequiredWidth -Button $control -HorizontalSafety 8
            if ($control.Width -lt $requiredWidth -or (([string]$control.Text).Contains('&') -and $control.UseMnemonic)) {
                Write-Output ([string]$control.Text)
            }
        }
        Get-EnterpriseClippedButtonLabels -Root $control
    }
}

function Fit-EnterpriseWindowToWorkingArea {
    $workArea = [Windows.Forms.Screen]::FromControl($form).WorkingArea
    $availableWidth = [Math]::Max(560, $workArea.Width - 12)
    $availableHeight = [Math]::Max(460, $workArea.Height - 12)
    $targetWidth = [Math]::Min(1120, $availableWidth)
    $targetHeight = [Math]::Min(780, $availableHeight)
    $form.MinimumSize = New-Object Drawing.Size([Math]::Min(760, $targetWidth), [Math]::Min(560, $targetHeight))
    $targetX = $workArea.Left + [Math]::Max(0, [Math]::Floor(($workArea.Width - $targetWidth) / 2))
    $targetY = $workArea.Top + [Math]::Max(0, [Math]::Floor(($workArea.Height - $targetHeight) / 2))
    $form.StartPosition = [Windows.Forms.FormStartPosition]::Manual
    $form.Bounds = New-Object Drawing.Rectangle($targetX, $targetY, $targetWidth, $targetHeight)
}

function Update-EnterpriseLayout {
    if ($script:updatingEnterpriseLayout -or -not $form -or -not $tabs) { return }
    $script:updatingEnterpriseLayout = $true
    try {
        $formWidth = [Math]::Max(640, $form.ClientSize.Width)
        $formHeight = [Math]::Max(500, $form.ClientSize.Height)
        Set-EnterpriseBounds $title 18 8 ($formWidth - 36) 32
        Set-EnterpriseBounds $script:enterpriseStatus 18 41 ([Math]::Max(300, $formWidth - 294)) 26
        Set-EnterpriseBounds $script:enterpriseNetworkButton ([Math]::Max(382, $formWidth - 258)) 38 240 30
        Set-EnterpriseBounds $tabs 10 72 ($formWidth - 20) ([Math]::Max(330, $formHeight - 124))
        $tabs.PerformLayout()

        if ($localManagerTab) {
            $localWidth = [Math]::Max(620, $localManagerTab.ClientSize.Width)
            $localLabels = @($localManagerTab.Controls | Where-Object { $_ -is [Windows.Forms.Label] })
            if ($localLabels.Count -gt 0) { Set-EnterpriseBounds $localLabels[0] 24 24 ($localWidth - 48) 30 }
            if ($localLabels.Count -gt 1) { Set-EnterpriseBounds $localLabels[1] 24 60 ($localWidth - 48) 42 }
            if ($localLabels.Count -gt 2) { Set-EnterpriseBounds $localLabels[2] 24 106 ($localWidth - 48) 34 }
            $localButtonWidth = [Math]::Min(($localWidth - 48), [Math]::Max(280, (Get-ToolUiButtonRequiredWidth -Button $localManagerButton)))
            Set-EnterpriseBounds $localManagerButton 24 154 $localButtonWidth 40
        }

        if ($serverTab) {
            $serverTab.AutoScroll = $false
            $width = [Math]::Max(680, $serverTab.ClientSize.Width)
            $height = [Math]::Max(470, $serverTab.ClientSize.Height)
            $margin = 16
            $gap = 8
            $contentWidth = $width - (2 * $margin)
            $narrow = [bool]($contentWidth -lt 820)

            $serverDescription = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.description")
            $serverNameLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.name")
            $serverAdminLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.adminCode")
            $serverPortLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.port")
            $serverCidrLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.cidrs")
            $pairingLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.pairingCode")
            $scanLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.scanLabel")
            $jobLabel = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.job")
            $createButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.create")
            $pairButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.pair")
            $startButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.start")
            $stopButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.stop")
            $deleteButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.delete")
            $networkButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.firewall")
            $refreshButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.refresh")
            $exportButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.export")
            $scanButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.scan")
            $createJobButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.createJob")

            Set-EnterpriseBounds $serverDescription $margin 4 $contentWidth 24
            $fieldY = 32
            if (-not $narrow) {
                $nameLabelWidth = 100
                $nameBoxWidth = [Math]::Min(230, [Math]::Max(170, [Math]::Floor($contentWidth * 0.22)))
                $adminLabelWidth = 165
                $adminBoxWidth = [Math]::Min(240, [Math]::Max(175, [Math]::Floor($contentWidth * 0.23)))
                $portLabelWidth = 42
                $portBoxWidth = 80
                $x = $margin
                Set-EnterpriseBounds $serverNameLabel $x $fieldY $nameLabelWidth 26
                $x += $nameLabelWidth
                Set-EnterpriseBounds $script:serverNameBox $x $fieldY $nameBoxWidth 26
                $x += $nameBoxWidth + $gap
                Set-EnterpriseBounds $serverAdminLabel $x $fieldY $adminLabelWidth 26
                $x += $adminLabelWidth
                Set-EnterpriseBounds $script:serverAdminBox $x $fieldY $adminBoxWidth 26
                $x += $adminBoxWidth + $gap
                Set-EnterpriseBounds $serverPortLabel $x $fieldY $portLabelWidth 26
                $x += $portLabelWidth
                Set-EnterpriseBounds $script:serverPortBox $x $fieldY $portBoxWidth 26
                $cidrLabelY = 63
            } else {
                $nameLabelWidth = 100
                $portLabelWidth = 42
                $portBoxWidth = 80
                $nameBoxWidth = $contentWidth - $nameLabelWidth - $portLabelWidth - $portBoxWidth - (2 * $gap)
                Set-EnterpriseBounds $serverNameLabel $margin $fieldY $nameLabelWidth 26
                Set-EnterpriseBounds $script:serverNameBox ($margin + $nameLabelWidth) $fieldY $nameBoxWidth 26
                Set-EnterpriseBounds $serverPortLabel ($margin + $nameLabelWidth + $nameBoxWidth + $gap) $fieldY $portLabelWidth 26
                Set-EnterpriseBounds $script:serverPortBox ($margin + $contentWidth - $portBoxWidth) $fieldY $portBoxWidth 26
                $adminY = $fieldY + 30
                Set-EnterpriseBounds $serverAdminLabel $margin $adminY 165 26
                Set-EnterpriseBounds $script:serverAdminBox ($margin + 165) $adminY ($contentWidth - 165) 26
                $cidrLabelY = 93
            }

            $cidrLabelWidth = [Math]::Floor($contentWidth * 0.58)
            Set-EnterpriseBounds $serverCidrLabel $margin $cidrLabelY $cidrLabelWidth 20
            Set-EnterpriseBounds $script:serverAddressLabel ($margin + $cidrLabelWidth) $cidrLabelY ($contentWidth - $cidrLabelWidth) 20
            $cidrBoxY = $cidrLabelY + 20
            Set-EnterpriseBounds $script:serverCidrBox $margin $cidrBoxY $contentWidth 40

            $actionY = $cidrBoxY + 45
            $actionRowCount = Set-EnterpriseAdaptiveButtonRows -Buttons @($createButton,$pairButton,$startButton,$stopButton,$deleteButton) -X $margin -Y $actionY -AvailableWidth $contentWidth -Height 34 -Gap $gap -RowGap 5

            $pairY = $actionY + ($actionRowCount * 34) + (($actionRowCount - 1) * 5) + 5
            $networkWidth = [Math]::Min(250, [Math]::Max((Get-ToolUiButtonRequiredWidth -Button $networkButton), [Math]::Floor($contentWidth * 0.21)))
            $pairLabelWidth = [Math]::Min(245, [Math]::Max(190, [Math]::Floor($contentWidth * 0.25)))
            Set-EnterpriseBounds $networkButton $margin $pairY $networkWidth 32
            Set-EnterpriseBounds $pairingLabel ($margin + $networkWidth + $gap) $pairY $pairLabelWidth 32
            Set-EnterpriseBounds $script:pairingOutputBox ($margin + $networkWidth + $gap + $pairLabelWidth) ($pairY + 3) ($contentWidth - $networkWidth - $gap - $pairLabelWidth) 26

            $scanLabelY = $pairY + 37
            Set-EnterpriseBounds $scanLabel $margin $scanLabelY $contentWidth 20
            $scanInputY = $scanLabelY + 21
            $scanButtonWidth = 130
            Set-EnterpriseBounds $script:scanInputBox $margin $scanInputY ($contentWidth - $scanButtonWidth - $gap) 28
            Set-EnterpriseBounds $scanButton ($margin + $contentWidth - $scanButtonWidth) $scanInputY $scanButtonWidth 30
            $scanResultY = $scanInputY + 34
            Set-EnterpriseBounds $script:scanResultBox $margin $scanResultY $contentWidth 44

            $clientHeaderY = $scanResultY + 49
            $refreshWidth = [Math]::Min(220, [Math]::Max(155, (Get-ToolUiButtonRequiredWidth -Button $refreshButton)))
            $exportWidth = [Math]::Min(220, [Math]::Max(170, (Get-ToolUiButtonRequiredWidth -Button $exportButton)))
            Set-EnterpriseBounds $script:clientCountLabel $margin $clientHeaderY ($contentWidth - $refreshWidth - $exportWidth - (2 * $gap)) 30
            Set-EnterpriseBounds $refreshButton ($margin + $contentWidth - $refreshWidth - $exportWidth - $gap) $clientHeaderY $refreshWidth 30
            Set-EnterpriseBounds $exportButton ($margin + $contentWidth - $exportWidth) $clientHeaderY $exportWidth 30

            $jobY = $height - 40
            $listY = $clientHeaderY + 34
            $listHeight = [Math]::Max(54, $jobY - $listY - 6)
            Set-EnterpriseBounds $script:serverClientList $margin $listY $contentWidth $listHeight

            $jobLabelWidth = 105
            $operationWidth = [Math]::Min(230, [Math]::Max(170, [Math]::Floor($contentWidth * 0.23)))
            $jobButtonWidth = [Math]::Min(285, [Math]::Max((Get-ToolUiButtonRequiredWidth -Button $createJobButton), [Math]::Floor($contentWidth * 0.24)))
            $jobKeyWidth = $contentWidth - $jobLabelWidth - $operationWidth - $jobButtonWidth - (2 * $gap)
            Set-EnterpriseBounds $jobLabel $margin $jobY $jobLabelWidth 30
            Set-EnterpriseBounds $script:jobOperationBox ($margin + $jobLabelWidth) $jobY $operationWidth 28
            Set-EnterpriseBounds $script:jobKeyBox ($margin + $jobLabelWidth + $operationWidth + $gap) $jobY $jobKeyWidth 28
            Set-EnterpriseBounds $createJobButton ($margin + $contentWidth - $jobButtonWidth) ($jobY - 2) $jobButtonWidth 34
            $serverContentBottom = $jobY + 40
            $serverTab.AutoScroll = [bool]($serverContentBottom -gt $serverTab.ClientSize.Height)
            $serverTab.AutoScrollMinSize = if ($serverTab.AutoScroll) { New-Object Drawing.Size(0, ($serverContentBottom + 8)) } else { New-Object Drawing.Size(0, 0) }
        }

        if ($clientTab) {
            $clientTab.AutoScroll = $false
            $clientWidth = [Math]::Max(680, $clientTab.ClientSize.Width)
            $clientMargin = 18
            $clientContentWidth = $clientWidth - (2 * $clientMargin)
            $clientDescription = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.description" @($script:enterpriseReleaseVersion))
            $clientAddressLabel = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.address")
            $clientPortLabel = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.port")
            $clientPairingLabel = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.pairingCode")
            $testButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.test")
            $discoverButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.discover")
            $enrollButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.enroll")
            $sendButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.send")
            $enableAgentButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.enableAgent")
            $disableAgentButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.disableAgent")
            $clientNotes = @($clientTab.Controls | Where-Object { $_ -is [Windows.Forms.Label] -and $_ -ne $clientDescription -and $_ -ne $clientAddressLabel -and $_ -ne $clientPortLabel -and $_ -ne $clientPairingLabel })

            Set-EnterpriseBounds $clientDescription $clientMargin 12 $clientContentWidth 30
            $addressY = 50
            $addressLabelWidth = 210
            $portLabelWidth = 45
            $portBoxWidth = 85
            $addressBoxWidth = $clientContentWidth - $addressLabelWidth - $portLabelWidth - $portBoxWidth - (2 * $gap)
            Set-EnterpriseBounds $clientAddressLabel $clientMargin $addressY $addressLabelWidth 28
            Set-EnterpriseBounds $script:clientAddressBox ($clientMargin + $addressLabelWidth) $addressY $addressBoxWidth 28
            Set-EnterpriseBounds $clientPortLabel ($clientMargin + $addressLabelWidth + $addressBoxWidth + $gap) $addressY $portLabelWidth 28
            Set-EnterpriseBounds $script:clientPortBox ($clientMargin + $clientContentWidth - $portBoxWidth) $addressY $portBoxWidth 28
            $pairingY = 86
            Set-EnterpriseBounds $clientPairingLabel $clientMargin $pairingY $addressLabelWidth 28
            Set-EnterpriseBounds $script:clientPairingBox ($clientMargin + $addressLabelWidth) $pairingY ($clientContentWidth - $addressLabelWidth) 28
            Set-EnterpriseBounds $script:clientRemoteChanges $clientMargin 124 $clientContentWidth 28
            Set-EnterpriseBounds $script:clientAutoSend $clientMargin 154 $clientContentWidth 28

            $buttonY = 194
            $clientButtonGap = 7
            $clientButtonRows = Set-EnterpriseAdaptiveButtonRows -Buttons @($discoverButton,$testButton,$enrollButton,$sendButton,$enableAgentButton,$disableAgentButton) -X $clientMargin -Y $buttonY -AvailableWidth $clientContentWidth -Height 36 -Gap $clientButtonGap -RowGap 6
            $clientNotesY = $buttonY + ($clientButtonRows * 36) + (($clientButtonRows - 1) * 6) + 14
            if ($clientNotes.Count -gt 0) { Set-EnterpriseBounds $clientNotes[0] $clientMargin $clientNotesY $clientContentWidth 42 }
            if ($clientNotes.Count -gt 1) { Set-EnterpriseBounds $clientNotes[1] $clientMargin ($clientNotesY + 44) $clientContentWidth 45 }
            $clientContentBottom = $clientNotesY + 89
            $clientTab.AutoScroll = [bool]($clientContentBottom -gt $clientTab.ClientSize.Height)
            $clientTab.AutoScrollMinSize = if ($clientTab.AutoScroll) { New-Object Drawing.Size(0, ($clientContentBottom + 8)) } else { New-Object Drawing.Size(0, 0) }
        }

        $footerY = [Math]::Max(80, $formHeight - 42)
        Set-EnterpriseBounds $backButton 18 $footerY 205 32
        Set-EnterpriseBounds $closeButton ([Math]::Max(225, $formWidth - 198)) $footerY 180 32
    } finally {
        $script:updatingEnterpriseLayout = $false
    }
}

$form = New-Object Windows.Forms.Form
$form.Text = Get-EnterpriseText "enterprise.form.title" @($script:enterpriseReleaseDisplayName)
$form.StartPosition = "CenterScreen"
$form.Size = New-Object Drawing.Size(1040, 760)
$form.MinimumSize = New-Object Drawing.Size(860, 620)
$form.Font = $script:enterpriseFont
$form.BackColor = $script:enterprisePalette.Form
$form.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
$form.AutoScroll = $false

$title = New-EnterpriseLabel (Get-EnterpriseText "enterprise.title" @($script:enterpriseReleaseDisplayName)) 18 8 700 32
$title.Font = $script:enterpriseTitleFont
$title.ForeColor = $script:enterprisePalette.Header
$form.Controls.Add($title)
$script:enterpriseStatus = New-EnterpriseLabel (Get-EnterpriseText "enterprise.status.choose") 18 41 840 26
$form.Controls.Add($script:enterpriseStatus)
$script:enterpriseNetworkButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.network.allow") 780 38 240 30 {
    [void](Toggle-EnterpriseNetworkAccess -SkipConfirmation:$SmokeTest)
}
$form.Controls.Add($script:enterpriseNetworkButton)

$tabs = New-Object Windows.Forms.TabControl
$tabs.Location = New-Object Drawing.Point(10, 72)
$tabs.Size = New-Object Drawing.Size(995, 560)
$tabs.Anchor = "Top,Bottom,Left,Right"
$tabs.DrawMode = [Windows.Forms.TabDrawMode]::OwnerDrawFixed
$tabs.SizeMode = [Windows.Forms.TabSizeMode]::Fixed
$tabs.ItemSize = New-Object Drawing.Size(245, 32)
$tabs.Padding = New-Object Drawing.Point(12, 4)
$form.Controls.Add($tabs)

# Chức năng 1: quản lý license cục bộ
$localManagerTab = New-Object Windows.Forms.TabPage
$localManagerTab.Text = Get-EnterpriseText "enterprise.local.tab"
$localManagerTab.BackColor = $script:enterprisePalette.LocalSurface
$localManagerTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.local.description") 24 24 930 30))
$localManagerTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.local.detail") 24 60 930 42))
$localSafetyLabel = New-EnterpriseLabel (Get-EnterpriseText "enterprise.local.safety") 24 106 930 34
$localSafetyLabel.ForeColor = $script:enterprisePalette.DangerText
$localManagerTab.Controls.Add($localSafetyLabel)
$localManagerButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.local.open") 24 154 280 40 {
    try {
        $env:TOOL_UI_THEME = $script:enterpriseTheme
        $local = Join-Path $baseDir "windows-office-license-manager.ps1"
        $launcher = Get-EnterpriseLauncherPath
        if ($launcher) {
            Start-Process -FilePath $launcher -ArgumentList "--local-license-manager" -Verb RunAs | Out-Null
        } else {
            Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy RemoteSigned -File `"$local`"" -Verb RunAs | Out-Null
        }
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.local.opened") $true
    } catch {
        Show-EnterpriseError (ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 900)
    }
}
$localManagerTab.Controls.Add($localManagerButton)
$tabs.TabPages.Add($localManagerTab) | Out-Null

# Chức năng 2: máy chủ
$serverTab = New-Object Windows.Forms.TabPage
$serverTab.Text = Get-EnterpriseText "enterprise.server.tab"
$serverTab.BackColor = $script:enterprisePalette.ServerSurface
$serverTab.AutoScroll = $false
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.description") 18 12 930 28))
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.name") 18 52))
$script:serverNameBox = New-EnterpriseTextBox 145 49 220
$script:serverNameBox.Text = [Environment]::MachineName
$serverTab.Controls.Add($script:serverNameBox)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.adminCode") 390 52 170))
$script:serverAdminBox = New-EnterpriseTextBox 565 49 210 25 $false $true
$serverTab.Controls.Add($script:serverAdminBox)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.port") 795 52 40))
$script:serverPortBox = New-EnterpriseTextBox 835 49 80
$script:serverPortBox.Text = [string]$script:ToolEnterpriseDefaultPort
$serverTab.Controls.Add($script:serverPortBox)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.cidrs") 18 88 470))
$script:serverAddressLabel = New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.addressChecking") 510 88 405
$script:serverAddressLabel.TextAlign = [Drawing.ContentAlignment]::TopRight
$serverTab.Controls.Add($script:serverAddressLabel)
$script:serverCidrBox = New-EnterpriseTextBox 18 115 350 70 $true
$serverTab.Controls.Add($script:serverCidrBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.create") 390 112 180 34 { Invoke-ServerCreate }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.pair") 580 112 160 34 { Invoke-ServerPairingCode }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.start") 750 112 165 34 { Invoke-ServerStart }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.stop") 750 150 165 34 { Stop-EnterpriseServer }))
$deleteServerButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.server.delete") 750 188 165 34 { Invoke-ServerDeleteConfiguration }
$deleteServerButton.ForeColor = $script:enterprisePalette.DangerText
$serverTab.Controls.Add($deleteServerButton)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.pairingCode") 390 157 250))
$script:pairingOutputBox = New-EnterpriseTextBox 390 182 350
$script:pairingOutputBox.ReadOnly = $true
$serverTab.Controls.Add($script:pairingOutputBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.firewall") 18 195 190 32 { Invoke-ServerNetworkAccess }))
$script:clientCountLabel = New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.pairedCount" @(0)) 195 201 300
$serverTab.Controls.Add($script:clientCountLabel)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.refresh") 510 195 160 32 { Update-ServerClientList }))
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.export") 680 195 170 32 { Invoke-ServerExport }))
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.scanLabel") 18 242 250))
$script:scanInputBox = New-EnterpriseTextBox 18 270 270
$script:scanInputBox.Text = ""
$serverTab.Controls.Add($script:scanInputBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.scan") 300 268 130 32 { Invoke-ServerScan }))
$script:scanResultBox = New-EnterpriseTextBox 18 307 900 78 $true
$script:scanResultBox.ReadOnly = $true
$script:scanResultBox.Font = $script:enterpriseSmallFont
$serverTab.Controls.Add($script:scanResultBox)
$script:serverClientList = New-Object Windows.Forms.ListView
$script:serverClientList.Location = New-Object Drawing.Point(18, 400)
$script:serverClientList.Size = New-Object Drawing.Size(900, 135)
$script:serverClientList.View = "Details"
$script:serverClientList.FullRowSelect = $true
$script:serverClientList.GridLines = $true
$script:serverClientList.Anchor = "Top,Left,Right"
foreach ($column in @(
    @((Get-EnterpriseText "enterprise.server.clientColumn"),150),
    @("IP",120),
    @((Get-EnterpriseText "enterprise.server.lastSeenColumn"),180),
    @("Windows / Office",190),
    @("ClientId",240)
)) {
    [void]$script:serverClientList.Columns.Add($column[0], [int]$column[1])
}
$serverTab.Controls.Add($script:serverClientList)
$serverTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.server.job") 18 548 140))
$script:jobOperationBox = New-Object Windows.Forms.ComboBox
$script:jobOperationBox.Location = New-Object Drawing.Point(145, 545)
$script:jobOperationBox.Size = New-Object Drawing.Size(230, 25)
$script:jobOperationBox.DropDownStyle = "DropDownList"
[void]$script:jobOperationBox.Items.Add("InventoryOnly")
[void]$script:jobOperationBox.Items.Add("WindowsInstallAndActivate")
[void]$script:jobOperationBox.Items.Add("OfficeInstallAndActivate")
$script:jobOperationBox.SelectedIndex = 0
$serverTab.Controls.Add($script:jobOperationBox)
$script:jobKeyBox = New-EnterpriseTextBox 390 545 250
$script:jobKeyBox.UseSystemPasswordChar = $true
$serverTab.Controls.Add($script:jobKeyBox)
$serverTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.server.createJob") 655 542 230 34 { Invoke-ServerJob }))
$tabs.TabPages.Add($serverTab) | Out-Null

# Chức năng 3: máy trạm
$clientTab = New-Object Windows.Forms.TabPage
$clientTab.Text = Get-EnterpriseText "enterprise.client.tab"
$clientTab.BackColor = $script:enterprisePalette.ClientSurface
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.description" @($script:enterpriseReleaseVersion)) 20 18 920 30))
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.address") 20 65 210))
$script:clientAddressBox = New-EnterpriseTextBox 180 62 260
$clientTab.Controls.Add($script:clientAddressBox)
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.port") 460 65 45))
$script:clientPortBox = New-EnterpriseTextBox 510 62 85
$script:clientPortBox.Text = [string]$script:ToolEnterpriseDefaultPort
$clientTab.Controls.Add($script:clientPortBox)
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.pairingCode") 20 105))
$script:clientPairingBox = New-EnterpriseTextBox 180 102 415
$script:clientPairingBox.UseSystemPasswordChar = $true
$clientTab.Controls.Add($script:clientPairingBox)
$script:clientRemoteChanges = New-Object Windows.Forms.CheckBox
$script:clientRemoteChanges.Text = Get-EnterpriseText "enterprise.client.remoteChanges"
$script:clientRemoteChanges.Location = New-Object Drawing.Point(20, 145)
$script:clientRemoteChanges.Size = New-Object Drawing.Size(520, 28)
$clientTab.Controls.Add($script:clientRemoteChanges)
$script:clientAutoSend = New-Object Windows.Forms.CheckBox
$script:clientAutoSend.Text = Get-EnterpriseText "enterprise.client.autoSend"
$script:clientAutoSend.Checked = $true
$script:clientAutoSend.Location = New-Object Drawing.Point(20, 177)
$script:clientAutoSend.Size = New-Object Drawing.Size(420, 28)
$clientTab.Controls.Add($script:clientAutoSend)
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.discover") 20 220 135 34 { Invoke-ClientDiscover }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.test") 165 220 145 34 { Invoke-ClientTest }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.enroll") 320 220 160 34 { Invoke-ClientEnroll }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.send") 490 220 145 34 { Invoke-ClientSend }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.enableAgent") 645 220 145 34 { Invoke-ClientSchedule $true }))
$clientTab.Controls.Add((New-EnterpriseButton (Get-EnterpriseText "enterprise.client.disableAgent") 800 220 145 34 { Invoke-ClientSchedule $false }))
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.queueNote") 20 285 850 45))
$clientTab.Controls.Add((New-EnterpriseLabel (Get-EnterpriseText "enterprise.client.keyNote") 20 335 850 45))
$tabs.TabPages.Add($clientTab) | Out-Null

$script:backButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.navigation.back") 18 0 205 32 { Invoke-EnterpriseBack }
$script:closeButton = New-EnterpriseButton (Get-EnterpriseText "enterprise.navigation.close") 0 0 180 32 { Invoke-EnterpriseClose }
$form.Controls.Add($script:backButton)
$form.Controls.Add($script:closeButton)

$tabs.Add_DrawItem({
    param($sender, $e)
    $page = $sender.TabPages[$e.Index]
    $selected = ($sender.SelectedIndex -eq $e.Index)
    $tabColor = if ($e.Index -eq 0) {
        $script:enterprisePalette.LocalButton
    } elseif ($e.Index -eq 1) {
        $script:enterprisePalette.ServerButton
    } else {
        $script:enterprisePalette.ClientButton
    }
    $backColor = if ($selected) { $tabColor } else { $script:enterprisePalette.Button }
    $foreColor = if ($selected) { [Drawing.Color]::White } else { $script:enterprisePalette.Text }
    $brush = New-Object Drawing.SolidBrush($backColor)
    $textBrush = New-Object Drawing.SolidBrush($foreColor)
    try {
        $e.Graphics.FillRectangle($brush, $e.Bounds)
        $format = New-Object Drawing.StringFormat
        $format.Alignment = [Drawing.StringAlignment]::Center
        $format.LineAlignment = [Drawing.StringAlignment]::Center
        # PowerShell có thể chọn nhầm overload PointF nếu truyền trực tiếp Rectangle.
        # Tạo RectangleF tường minh để tương thích Windows PowerShell 5.1/WinForms.
        $boundsF = New-Object Drawing.RectangleF
        $boundsF.X = [float]$e.Bounds.X
        $boundsF.Y = [float]$e.Bounds.Y
        $boundsF.Width = [float]$e.Bounds.Width
        $boundsF.Height = [float]$e.Bounds.Height
        $e.Graphics.DrawString($page.Text, $sender.Font, $textBrush, $boundsF, $format)
        $format.Dispose()
    } finally {
        $brush.Dispose()
        $textBrush.Dispose()
    }
})

foreach ($button in @($localManagerTab.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
    Set-EnterpriseButtonStyle $button $script:enterprisePalette.LocalButton ([Drawing.Color]::White) $script:enterprisePalette.LocalHover
}
foreach ($button in @($serverTab.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
    Set-EnterpriseButtonStyle $button $script:enterprisePalette.ServerButton ([Drawing.Color]::White) $script:enterprisePalette.ServerHover
}
foreach ($button in @($clientTab.Controls | Where-Object { $_ -is [Windows.Forms.Button] })) {
    Set-EnterpriseButtonStyle $button $script:enterprisePalette.ClientButton ([Drawing.Color]::White) $script:enterprisePalette.ClientHover
}
$deleteServerButton = Find-EnterpriseDirectControl $serverTab (Get-EnterpriseText "enterprise.server.delete")
Set-EnterpriseButtonStyle $deleteServerButton $script:enterprisePalette.Danger ([Drawing.Color]::White) $script:enterprisePalette.DangerHover
Set-EnterpriseButtonStyle $script:backButton $script:enterprisePalette.Navigation ([Drawing.Color]::White) $script:enterprisePalette.NavigationHover
Set-EnterpriseButtonStyle $script:closeButton $script:enterprisePalette.Danger ([Drawing.Color]::White) $script:enterprisePalette.DangerHover
Update-EnterpriseNetworkStateUi -UpdateStatus
$script:serverClientList.BackColor = $script:enterprisePalette.Surface
$script:serverClientList.ForeColor = $script:enterprisePalette.Text
$script:jobOperationBox.BackColor = $script:enterprisePalette.Input
$script:jobOperationBox.ForeColor = $script:enterprisePalette.Text
$script:clientRemoteChanges.ForeColor = $script:enterprisePalette.Text
$script:clientAutoSend.ForeColor = $script:enterprisePalette.Text
Register-ToolUiDynamicContrast -Root $form -Mode $script:enterpriseTheme

$form.Add_Shown({
    try {
        Fit-EnterpriseWindowToWorkingArea
        Update-EnterpriseLayout
        [void](Update-EnterpriseDetectedServerAddress)
        $cfg = Get-EnterpriseServerConfigurationSafe
        if ($cfg) {
            $script:serverNameBox.Text = [string]$cfg.ServerName
            $script:serverPortBox.Text = [string]$cfg.Port
            $script:serverCidrBox.Text = (@($cfg.AllowedCidrs) -join [Environment]::NewLine)
        }
        if ([string]::IsNullOrWhiteSpace($script:scanInputBox.Text)) {
            $defaultCidrs = if ($cfg) { @($cfg.AllowedCidrs) } else { @(Get-ToolEnterpriseLocalCidrs) }
            if ($defaultCidrs.Count -gt 0) { $script:scanInputBox.Text = [string]$defaultCidrs[0] }
        }
        $clientCfg = Get-ToolEnterpriseClientConfig
        if ($clientCfg) {
            $script:clientAddressBox.Text = [string]$clientCfg.ServerAddress
            $script:clientPortBox.Text = [string]$clientCfg.Port
            $script:clientRemoteChanges.Checked = [bool]$clientCfg.AllowRemoteLicenseChanges
            $script:clientAutoSend.Checked = [bool]$clientCfg.AutoSend
        }
        Update-ServerClientList
        Update-EnterpriseLayout
    } catch {}
})
$form.Add_Resize({ Update-EnterpriseLayout })
$tabs.Add_SelectedIndexChanged({
    $script:previousTabIndex = $tabs.SelectedIndex
    $tabs.Invalidate()
    if (-not $script:enterpriseNetworkAllowed -and $tabs.SelectedIndex -gt 0) {
        Set-EnterpriseStatus (Get-EnterpriseText "enterprise.network.blockedStatus") $true
    }
    Update-EnterpriseLayout
})
$form.Add_Activated({ [void](Update-EnterpriseDetectedServerAddress) })
$form.Add_FormClosed({
    foreach ($font in @($script:enterpriseFont,$script:enterpriseSmallFont,$script:enterpriseTitleFont)) { try { $font.Dispose() } catch {} }
})
if ($SmokeTest) {
    if ($tabs.TabPages.Count -ne 3) { throw (Get-EnterpriseText "enterpriseSmoke.tabCount") }
    if ($tabs.TabPages[0].Text -ne (Get-EnterpriseText "enterprise.local.tab") -or
        $tabs.TabPages[1].Text -ne (Get-EnterpriseText "enterprise.server.tab") -or
        $tabs.TabPages[2].Text -ne (Get-EnterpriseText "enterprise.client.tab")) {
        throw (Get-EnterpriseText "enterpriseSmoke.tabNames")
    }
    if (-not $localManagerButton -or $localManagerButton.Text -ne (Get-EnterpriseText "enterprise.local.open")) {
        throw (Get-EnterpriseText "enterpriseSmoke.localManagerMissing")
    }
    if (-not $backButton -or -not $closeButton) { throw (Get-EnterpriseText "enterpriseSmoke.navigationMissing") }
    if (-not $script:enterpriseNetworkButton -or -not $form.Controls.Contains($script:enterpriseNetworkButton)) {
        throw (Get-EnterpriseText "enterpriseSmoke.networkControlMissing")
    }
    if (-not $script:enterpriseNetworkAllowed -and (-not $serverTab.Enabled -or -not $clientTab.Enabled)) {
        throw (Get-EnterpriseText "enterpriseSmoke.offlineTabsUnavailable")
    }
    if ($form.BackColor.ToArgb() -ne $script:enterprisePalette.Form.ToArgb() -or
        $localManagerTab.BackColor.ToArgb() -ne $script:enterprisePalette.LocalSurface.ToArgb() -or
        $serverTab.BackColor.ToArgb() -ne $script:enterprisePalette.ServerSurface.ToArgb() -or
        $clientTab.BackColor.ToArgb() -ne $script:enterprisePalette.ClientSurface.ToArgb()) {
        throw (Get-EnterpriseText "enterpriseSmoke.themeCoverage" @($script:enterpriseTheme))
    }
    if ($script:serverNameBox.BackColor.ToArgb() -ne $script:enterprisePalette.Input.ToArgb() -or
        $script:serverClientList.BackColor.ToArgb() -ne $script:enterprisePalette.Surface.ToArgb()) {
        throw (Get-EnterpriseText "enterpriseSmoke.themeInputs" @($script:enterpriseTheme))
    }
    if ((Get-ToolUiContrastRatio -Foreground $script:enterprisePalette.Text -Background $script:enterprisePalette.Form) -lt 4.5 -or
        (Get-ToolUiContrastRatio -Foreground $script:enterprisePalette.Text -Background $script:enterprisePalette.Input) -lt 4.5) {
        throw (Get-EnterpriseText "enterpriseSmoke.themeContrast" @($script:enterpriseTheme))
    }
    $form.Opacity = 0
    $form.ShowInTaskbar = $false
    $form.Show()
    [Windows.Forms.Application]::DoEvents()
    $form.ClientSize = New-Object Drawing.Size(980, 620)
    Update-EnterpriseLayout
    $tabs.Refresh()
    [Windows.Forms.Application]::DoEvents()
    if ([string]::IsNullOrWhiteSpace($script:scanInputBox.Text)) {
        throw (Get-EnterpriseText "enterpriseSmoke.defaultCidrMissing")
    }
    if ($serverTab.AutoScroll -or $serverTab.HorizontalScroll.Visible) { throw (Get-EnterpriseText "enterpriseSmoke.horizontalScroll") }
    foreach ($buttonText in @(
        (Get-EnterpriseText "enterprise.server.create"),
        (Get-EnterpriseText "enterprise.server.pair"),
        (Get-EnterpriseText "enterprise.server.start"),
        (Get-EnterpriseText "enterprise.server.stop"),
        (Get-EnterpriseText "enterprise.server.delete"),
        (Get-EnterpriseText "enterprise.server.firewall"),
        (Get-EnterpriseText "enterprise.server.scan"),
        (Get-EnterpriseText "enterprise.server.refresh"),
        (Get-EnterpriseText "enterprise.server.export"),
        (Get-EnterpriseText "enterprise.server.createJob")
    )) {
        $button = Find-EnterpriseDirectControl $serverTab $buttonText
        if (-not $button -or $button.Width -lt 60 -or $button.Right -gt ($serverTab.ClientSize.Width + 1)) {
            throw (Get-EnterpriseText "enterpriseSmoke.buttonClipped" @($buttonText))
        }
    }
    if ($script:serverClientList.Bottom -gt ($serverTab.ClientSize.Height + 1) -or $script:jobKeyBox.Right -gt ($serverTab.ClientSize.Width + 1)) {
        throw (Get-EnterpriseText "enterpriseSmoke.serverLayoutClipped")
    }
    $discoverButton = Find-EnterpriseDirectControl $clientTab (Get-EnterpriseText "enterprise.client.discover")
    if (-not $discoverButton -or $discoverButton.Right -gt ($clientTab.ClientSize.Width + 1)) {
        throw (Get-EnterpriseText "enterpriseSmoke.discoverClipped")
    }
    foreach ($tabIndex in 0..2) {
        $tabs.SelectedIndex = $tabIndex
        Update-EnterpriseLayout
        [Windows.Forms.Application]::DoEvents()
    }
    $clippedButtonLabels = @(Get-EnterpriseClippedButtonLabels -Root $form | Select-Object -Unique)
    if ($clippedButtonLabels.Count -gt 0) {
        throw (Get-EnterpriseText "enterpriseSmoke.buttonClipped" @(($clippedButtonLabels -join ', ')))
    }
    $tabs.SelectedIndex = 2
    $backButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if ($tabs.SelectedIndex -ne 1) { throw (Get-EnterpriseText "enterpriseSmoke.backNavigation") }
    if ($closeButton.Text -ne (Get-EnterpriseText "enterprise.navigation.close")) { throw (Get-EnterpriseText "enterpriseSmoke.closeLabel") }
    $networkStateBefore = [bool]$script:enterpriseNetworkAllowed
    $script:enterpriseNetworkButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if ([bool]$script:enterpriseNetworkAllowed -eq $networkStateBefore) { throw (Get-EnterpriseText "enterpriseSmoke.networkDidNotToggle") }
    $script:enterpriseNetworkButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if ([bool]$script:enterpriseNetworkAllowed -ne $networkStateBefore) { throw (Get-EnterpriseText "enterpriseSmoke.networkDidNotRestore") }
    if ($script:enterpriseCulture -eq "en-US") {
        $visibleText = New-Object System.Collections.Generic.List[string]
        $controlQueue = New-Object System.Collections.Queue
        $controlQueue.Enqueue($form)
        while ($controlQueue.Count -gt 0) {
            $currentControl = $controlQueue.Dequeue()
            if (-not [string]::IsNullOrWhiteSpace([string]$currentControl.Text)) {
                [void]$visibleText.Add([string]$currentControl.Text)
            }
            foreach ($childControl in $currentControl.Controls) { $controlQueue.Enqueue($childControl) }
        }
        foreach ($column in $script:serverClientList.Columns) {
            if (-not [string]::IsNullOrWhiteSpace([string]$column.Text)) { [void]$visibleText.Add([string]$column.Text) }
        }
        $englishSurface = $visibleText -join "`n"
        if ($englishSurface -cmatch '[À-ỹ]') {
            throw (Get-EnterpriseText "enterpriseSmoke.englishLeak" @($englishSurface))
        }
    }
    Write-Output (Get-EnterpriseText "enterpriseSmoke.pass" @($script:enterpriseCulture, $script:enterpriseNetworkAllowed, $script:enterpriseTheme))
    $closeButton.PerformClick()
    [Windows.Forms.Application]::DoEvents()
    if (-not $form.IsDisposed -and $form.Visible) { throw (Get-EnterpriseText "enterpriseSmoke.closeFailed") }
    foreach ($font in @($script:enterpriseFont,$script:enterpriseSmallFont,$script:enterpriseTitleFont)) { try { $font.Dispose() } catch {} }
    $form.Dispose()
    exit 0
}
[void]$form.ShowDialog()
