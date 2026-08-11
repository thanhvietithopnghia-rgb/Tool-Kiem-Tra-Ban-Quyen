[CmdletBinding()]
param(
    [string]$SourceDirectory = ''
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version 2.0
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }

function Assert-Enterprise {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

$required = @(
    "Tool-Enterprise.ps1",
    "Tool-EnterpriseHost.ps1",
    "Tool-EnterpriseAgent.ps1",
    "enterprise-license-manager.ps1",
    "windows-office-license-manager.ps1",
    "Tool-Localization.ps1",
    "Tool-Strings.vi-VN.json",
    "Tool-Strings.en-US.json",
    "Tool-OfflinePolicy.ps1",
    "Tool-UiTheme.ps1",
    "Tool-ReportSchema.ps1",
    "Tool-ModuleContract.ps1",
    "Tool-Kiem-Tra-v4.8-OneFile.cs"
)
foreach ($name in $required) {
    $path = Join-Path $SourceDirectory $name
    Assert-Enterprise (Test-Path -LiteralPath $path -PathType Leaf) "Thiếu tệp enterprise: $name"
    if ($name.EndsWith(".ps1", [StringComparison]::OrdinalIgnoreCase)) {
        $errors = $null
        [void][Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$errors)
        Assert-Enterprise (@($errors).Count -eq 0) "PowerShell parse lỗi trong ${name}: $(@($errors | ForEach-Object ToString) -join '; ')"
    }
}

$previousRoot = [string]$env:TOOL_ENTERPRISE_ROOT
$previousSkipAcl = [string]$env:TOOL_ENTERPRISE_SKIP_ACL
$previousOfflineMode = [string]$env:TOOL_OFFLINE_MODE
$previousEnterpriseNetworkAllowed = [string]$env:TOOL_ENTERPRISE_NETWORK_ALLOWED
$previousEnterpriseNetworkSettings = [string]$env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH
$previousUiCulture = [string]$env:TOOL_UI_CULTURE
$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd("\") + "\"
$testRoot = Join-Path $temporaryBase ("ThanhViet-v48-enterprise-test-" + [Guid]::NewGuid().ToString("N"))
$exportRoot = Join-Path $temporaryBase ("ThanhViet-v48-enterprise-export-" + [Guid]::NewGuid().ToString("N"))
$separateClientRoot = Join-Path $temporaryBase ("ThanhViet-v48-enterprise-client-test-" + [Guid]::NewGuid().ToString("N"))
$hostProcess = $null
try {
    $env:TOOL_ENTERPRISE_ROOT = $testRoot
    $env:TOOL_ENTERPRISE_SKIP_ACL = "1"
    $env:TOOL_OFFLINE_MODE = "0"
    $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $testRoot "enterprise-network-settings.json"
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "0"
    . (Join-Path $SourceDirectory "Tool-ReportSchema.ps1")
    . (Join-Path $SourceDirectory "Tool-ModuleContract.ps1")
    . (Join-Path $SourceDirectory "Tool-Enterprise.ps1")

    $metadata = Get-ToolEnterpriseMetadata
    Assert-Enterprise ([string]$metadata.ToolVersion -eq "4.8.0.0") "Enterprise ToolVersion không phải 4.8.0.0."
    Assert-Enterprise ([string]$metadata.ProtocolVersion -eq "1.0") "Enterprise protocol không phải 1.0."
    Assert-Enterprise (-not [bool]$metadata.FullProductKeysInReports) "Metadata không được cho phép full product key trong báo cáo."

    $resolvedEndpoint = Resolve-ToolEnterpriseServerEndpoint -ServerAddress "192.168.2.5:49421" -Port 49420
    Assert-Enterprise ([string]$resolvedEndpoint.Address -eq "192.168.2.5" -and [int]$resolvedEndpoint.Port -eq 49421) "Không tách đúng địa chỉ IP:cổng của máy chủ."
    $invalidEndpoint = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress "địa chỉ không hợp lệ" -Port 49420 -TimeoutMs 200
    Assert-Enterprise (-not [bool]$invalidEndpoint.Success -and [string]$invalidEndpoint.Code -eq "InvalidEndpoint") "Chẩn đoán không phân biệt địa chỉ máy chủ không hợp lệ."

    $server = New-ToolEnterpriseServerConfiguration -ServerName "EnterpriseVerification" -AdminCode "Verify-Admin-4826" -BindAddress "127.0.0.1" -Port 49542 -AllowedCidrs @("127.0.0.0/8")
    Assert-Enterprise (Test-ToolEnterpriseAdminCode -AdminCode "Verify-Admin-4826" -Verifier $server.AdminVerifier) "Không xác minh được mã quản trị đúng."
    Assert-Enterprise (-not (Test-ToolEnterpriseAdminCode -AdminCode "Wrong-Admin" -Verifier $server.AdminVerifier)) "Mã quản trị sai lại được chấp nhận."
    $pairing = Get-ToolEnterprisePairingCode -AdminCode "Verify-Admin-4826"
    Assert-Enterprise ($pairing.Length -ge 20) "Mã ghép nối quá ngắn."

    $client = Set-ToolEnterpriseClientConfiguration -ServerAddress "127.0.0.1" -Port 49542 -AllowRemoteLicenseChanges:$false
    $clientAgain = Set-ToolEnterpriseClientConfiguration -ServerAddress "127.0.0.1" -Port 49542 -AllowRemoteLicenseChanges:$false
    Assert-Enterprise ([string]$client.ClientId -eq [string]$clientAgain.ClientId) "ClientId bị đổi khi cập nhật cấu hình."

    $paths = Get-ToolEnterprisePaths
    Assert-Enterprise ([string]$paths.ClientAgentResult -match 'agent-result\.json$' -and [string]$paths.ClientAgentError -match 'agent-error\.json$') "Lõi enterprise thiếu tệp xác nhận kết quả agent."
    $secret = Get-ToolEnterpriseSecret -Path $paths.ServerMasterSecret
    $envelope = New-ToolEnterpriseEnvelope -Secret $secret -Context "verify" -Payload ([ordered]@{ Value="round-trip"; Number=42 })
    $opened = Open-ToolEnterpriseEnvelope -Secret $secret -ExpectedContext "verify" -Envelope $envelope
    Assert-Enterprise ([string]$opened.Payload.Value -eq "round-trip") "Mã hóa enterprise không round-trip."
    $tampered = $envelope | Select-Object *
    $macText = [string]$tampered.Mac
    $tampered.Mac = $(if ($macText.Substring(0, 1) -eq "A") { "B" + $macText.Substring(1) } else { "A" + $macText.Substring(1) })
    $tamperRejected = $false
    try { [void](Open-ToolEnterpriseEnvelope -Secret $secret -ExpectedContext "verify" -Envelope $tampered) } catch { $tamperRejected = $true }
    Assert-Enterprise $tamperRejected "Envelope bị sửa HMAC không bị từ chối."

    $report = Get-ToolEnterpriseLicenseSnapshot -ClientId $client.ClientId
    $queuedReportPath = Add-ToolEnterpriseOutboxReport -Report $report
    Assert-Enterprise (Test-Path -LiteralPath $queuedReportPath -PathType Leaf) "Mất kết nối không tạo được hàng đợi báo cáo."
    Assert-Enterprise ((Get-Content -LiteralPath $queuedReportPath -Raw) -notmatch 'EnterpriseInventory') "Hàng đợi báo cáo lưu dữ liệu rõ thay vì bảo vệ bằng DPAPI."
    $validation = Test-ToolReportEnvelope -Report $report -ExpectedReportKind "EnterpriseInventory" -ExpectedToolVersion "4.8.0.0"
    Assert-Enterprise ([bool]$validation.Valid) "Báo cáo EnterpriseInventory không đạt schema: $($validation.Errors -join '; ')"
    Assert-Enterprise (-not [bool]$report.Privacy.FullProductKeyIncluded) "Báo cáo khai báo chứa full product key."
    $reportJson = $report | ConvertTo-Json -Depth 14
    Assert-Enterprise ($reportJson -notmatch '(?i)[A-Z0-9]{5}(?:-[A-Z0-9]{5}){4}') "Báo cáo chứa chuỗi giống full product key."

    # Chạy listener thật trên loopback để kiểm tra toàn bộ đường đi từng bị lỗi
    # GetRequestStream: chẩn đoán TCP/dịch vụ, ghép nối và gửi báo cáo.
    $nativePowerShell = Join-Path $PSHOME "powershell.exe"
    if (-not (Test-Path -LiteralPath $nativePowerShell -PathType Leaf)) {
        $nativePowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source
    }
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = "1"
    $hostOutput = Join-Path $testRoot "host.stdout.log"
    $hostError = Join-Path $testRoot "host.stderr.log"
    $hostScript = Join-Path $SourceDirectory "Tool-EnterpriseHost.ps1"
    $hostArguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$hostScript`""
    $hostProcess = Start-Process -FilePath $nativePowerShell -ArgumentList $hostArguments -WorkingDirectory $SourceDirectory -WindowStyle Hidden -PassThru -RedirectStandardOutput $hostOutput -RedirectStandardError $hostError
    $liveDiagnostic = $null
    $liveDeadline = [DateTime]::UtcNow.AddSeconds(10)
    do {
        Start-Sleep -Milliseconds 150
        if ($hostProcess.HasExited) { break }
        $liveDiagnostic = Get-ToolEnterpriseConnectionDiagnostic -ServerAddress "127.0.0.1:49542" -Port 49420 -TimeoutMs 700
    } while (($null -eq $liveDiagnostic -or -not [bool]$liveDiagnostic.Success) -and [DateTime]::UtcNow -lt $liveDeadline)
    $hostFailure = ""
    if (Test-Path -LiteralPath $hostError -PathType Leaf) {
        $hostFailure = [string](Get-Content -LiteralPath $hostError -Raw -ErrorAction SilentlyContinue)
        if ($null -eq $hostFailure) { $hostFailure = "" } else { $hostFailure = $hostFailure.Trim() }
    }
    $diagnosticSummary = if ($null -ne $liveDiagnostic) { "$([string]$liveDiagnostic.Code) $([string]$liveDiagnostic.Message)" } else { "không tạo được kết quả chẩn đoán" }
    Assert-Enterprise ($null -ne $liveDiagnostic -and [bool]$liveDiagnostic.Success) "Listener loopback không sẵn sàng: $diagnosticSummary $hostFailure"
    $registeredClient = Register-ToolEnterpriseClient -ServerAddress "127.0.0.1:49542" -Port 49420 -PairingCode $pairing -AllowRemoteLicenseChanges:$false -AutoSend:$true
    Assert-Enterprise ([bool]$registeredClient.Enrolled -and [string]$registeredClient.ClientId -eq [string]$client.ClientId) "Máy trạm không ghép nối được với listener thật."
    $sendResponse = Send-ToolEnterpriseReport -Report $report
    Assert-Enterprise ([bool]$sendResponse.Accepted) "Listener thật không nhận báo cáo máy trạm."
    $receivedReports = @(Get-ChildItem -LiteralPath (Join-Path $paths.ServerReports $client.ClientId) -Filter "*.json" -File -ErrorAction SilentlyContinue)
    Assert-Enterprise ($receivedReports.Count -ge 1) "Máy chủ không lưu báo cáo nhận qua HTTP."

    # Mô phỏng đúng hai máy: tiến trình máy chủ vẫn dùng $testRoot, còn mọi
    # cấu hình/secret/outbox của máy trạm nằm ở một root hoàn toàn độc lập.
    $separateClientId = ''
    try {
        $env:TOOL_ENTERPRISE_ROOT = $separateClientRoot
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $separateClientRoot 'enterprise-network-settings.json'
        $separateClient = Register-ToolEnterpriseClient -ServerAddress '127.0.0.1:49542' -Port 49420 -PairingCode $pairing -AllowRemoteLicenseChanges:$false -AutoSend:$true
        $separateClientId = [string]$separateClient.ClientId
        $separatePaths = Get-ToolEnterprisePaths
        Assert-Enterprise ([bool]$separateClient.Enrolled -and (Test-Path -LiteralPath $separatePaths.ClientSecret -PathType Leaf)) 'Máy trạm ở kho dữ liệu độc lập không ghép nối/ghi secret được.'
        Assert-Enterprise ([string]$separatePaths.Root -ne [string]$paths.Root -and
            [string]$separatePaths.ClientConfig -like (([string]$separatePaths.Root).TrimEnd('\') + '\*')) 'Fixture máy trạm còn vô tình dùng chung kho dữ liệu với máy chủ.'
        $separateReport = Get-ToolEnterpriseLicenseSnapshot -ClientId $separateClientId
        $separateSendResponse = Send-ToolEnterpriseReport -Report $separateReport
        Assert-Enterprise ([bool]$separateSendResponse.Accepted) 'Máy trạm có kho dữ liệu độc lập không gửi được báo cáo.'
    } finally {
        $env:TOOL_ENTERPRISE_ROOT = $testRoot
        $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = Join-Path $testRoot 'enterprise-network-settings.json'
    }
    $paths = Get-ToolEnterprisePaths
    $separateReceivedReports = @(Get-ChildItem -LiteralPath (Join-Path $paths.ServerReports $separateClientId) -Filter '*.json' -File -ErrorAction SilentlyContinue)
    Assert-Enterprise ($separateReceivedReports.Count -ge 1) 'Máy chủ không lưu báo cáo gửi từ máy trạm có kho dữ liệu độc lập.'

    $clientSecret = New-ToolEnterpriseRandomBytes -Length 32
    Set-ToolEnterpriseServerClientSecret -ClientId $client.ClientId -Secret $clientSecret
    $record = [pscustomobject][ordered]@{
    SchemaVersion="1.0"; ToolVersion="4.8.0.0"; ClientId=$client.ClientId; ComputerName="VERIFY-CLIENT"
        RemoteAddress="127.0.0.1"; NetworkAddresses=@("127.0.0.1"); LastSeenUtc=[DateTime]::UtcNow.ToString("o")
        FirstSeenUtc=[DateTime]::UtcNow.ToString("o"); AllowRemoteLicenseChanges=$true
        WindowsStatus="NotReported"; WindowsChannel=""; WindowsLast5=""
        OfficeStatus="NotReported"; OfficeChannel=""; OfficeLast5=""; LatestReportPath=""
    }
    Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $client.ClientId) -Value $record
    $testKey = "AAAAA-BBBBB-CCCCC-DDDDD-EEEEE"
    $job = New-ToolEnterpriseLicenseJob -ClientId $client.ClientId -Operation "WindowsInstallAndActivate" -ProductKey $testKey -RequestedBy "Verifier"
    $jobPath = Join-Path (Join-Path $paths.ServerJobs $client.ClientId) ($job.JobId + ".job")
    $jobText = Get-Content -LiteralPath $jobPath -Raw
    Assert-Enterprise ($jobText -notmatch [regex]::Escape($testKey)) "Job trên đĩa làm lộ full product key."
    $jobPackage = Get-ToolEnterprisePendingJobPackage -ClientId $client.ClientId
    $jobOpened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext ("job:{0}:{1}" -f $client.ClientId, $job.JobId) -Envelope $jobPackage.Envelope -MaximumAgeMinutes 10
    Assert-Enterprise ([string]$jobOpened.Payload.ProductKey -eq $testKey) "Máy trạm không giải mã đúng payload tác vụ."
    Assert-Enterprise ([string]$job.ProductKeyLast5 -eq "EEEEE") "Tác vụ không trả đúng last5."
    $auditText = Get-Content -LiteralPath $paths.ServerAudit -Raw
    Assert-Enterprise ($auditText -notmatch [regex]::Escape($testKey)) "Audit làm lộ full product key."

    $cidr = Get-ToolEnterpriseCidrInfo -Cidr "10.20.41.24/22"
    Assert-Enterprise ([string]$cidr.Cidr -eq "10.20.40.0/22") "Chuẩn hóa CIDR /22 sai."
    Assert-Enterprise ([uint64]$cidr.HostCount -eq 1022) "Số host CIDR /22 sai."
    Assert-Enterprise (Test-ToolEnterpriseIpInCidr -Address "10.20.43.254" -Cidr $cidr.Cidr) "Kiểm tra IP trong CIDR sai."
    $tooLargeRejected = $false
    try { [void](Get-ToolEnterpriseCidrAddresses -Cidr "10.0.0.0/16") } catch { $tooLargeRejected = $true }
    Assert-Enterprise $tooLargeRejected "Quét vượt 1024 host không bị chặn."
    $localProfiles = @(Get-ToolEnterpriseLocalIPv4Profiles)
    foreach ($profile in $localProfiles) {
        Assert-Enterprise (Test-ToolEnterpriseHostName -Value ([string]$profile.Address)) "Nhận diện card mạng trả IPv4 không hợp lệ."
        Assert-Enterprise (Test-ToolEnterpriseIpInCidr -Address ([string]$profile.Address) -Cidr ([string]$profile.Cidr)) "IPv4 tự nhận không thuộc CIDR tương ứng."
    }
    if ($localProfiles.Count -gt 0) {
        Assert-Enterprise ([string](Get-ToolEnterprisePreferredServerAddress) -eq [string]$localProfiles[0].Address) "IP máy chủ ưu tiên không khớp thứ tự card mạng."
    }
    foreach ($discoveryCidr in @(Get-ToolEnterpriseLocalDiscoveryCidrs)) {
        Assert-Enterprise ([uint64](Get-ToolEnterpriseCidrInfo -Cidr $discoveryCidr).HostCount -le 1024) "CIDR tự dò máy chủ vượt giới hạn 1024 host."
    }

    New-Item -ItemType Directory -Path $exportRoot -Force | Out-Null
    $export = Export-ToolEnterpriseFleetReport -DestinationDirectory $exportRoot
    foreach ($path in @($export.JsonPath,$export.CsvPath,$export.HtmlPath,$export.ManifestPath)) {
        Assert-Enterprise (Test-Path -LiteralPath $path -PathType Leaf) "Thiếu artefact fleet: $path"
    }

    $preservedReportPath = Join-Path (Join-Path $paths.ServerReports $client.ClientId) "preserve-after-reset.json"
    $preservedResultPath = Join-Path (Join-Path $paths.ServerResults $client.ClientId) "preserve-after-reset.json"
    Write-ToolEnterpriseJson -Path $preservedReportPath -Value ([ordered]@{ Kind="PreservedReport"; ClientId=$client.ClientId })
    Write-ToolEnterpriseJson -Path $preservedResultPath -Value ([ordered]@{ Kind="PreservedResult"; ClientId=$client.ClientId })

    $wrongResetRejected = $false
    try { [void](Remove-ToolEnterpriseServerConfiguration -AdminCode "Wrong-Admin" -StopTimeoutSeconds 1) }
    catch { $wrongResetRejected = $true }
    Assert-Enterprise $wrongResetRejected "Mã quản trị sai lại xóa được cấu hình máy chủ."
    Assert-Enterprise (Test-Path -LiteralPath $paths.ServerConfig -PathType Leaf) "Lần xóa bằng mã sai đã làm mất server.json."
    Assert-Enterprise (Test-Path -LiteralPath $paths.ServerMasterSecret -PathType Leaf) "Lần xóa bằng mã sai đã làm mất master secret."

    $reset = Remove-ToolEnterpriseServerConfiguration -AdminCode "Verify-Admin-4826" -StopTimeoutSeconds 1
    Assert-Enterprise ([bool]$reset.Removed) "Hàm xóa cấu hình không trả trạng thái thành công."
    Assert-Enterprise ([bool]$reset.AuditWritten) "Xóa cấu hình không ghi được audit hoàn tất."
    foreach ($removedPath in @($paths.ServerConfig,$paths.ServerMasterSecret,$paths.ServerPairingSecret,$paths.ServerPid,$paths.ServerHeartbeat,$paths.ServerStop,$paths.ServerError)) {
        Assert-Enterprise (-not (Test-Path -LiteralPath $removedPath -PathType Leaf)) "Xóa cấu hình còn sót tệp: $removedPath"
    }
    foreach ($clearedDirectory in @($paths.ServerClients,$paths.ServerClientSecrets,$paths.ServerJobs)) {
        Assert-Enterprise (@(Get-ChildItem -LiteralPath $clearedDirectory -Force -Recurse -ErrorAction SilentlyContinue).Count -eq 0) "Xóa cấu hình còn trạng thái hoạt động trong: $clearedDirectory"
    }
    Assert-Enterprise (Test-Path -LiteralPath $preservedReportPath -PathType Leaf) "Xóa cấu hình làm mất báo cáo lịch sử."
    Assert-Enterprise (Test-Path -LiteralPath $preservedResultPath -PathType Leaf) "Xóa cấu hình làm mất kết quả lịch sử."
    Assert-Enterprise (Test-Path -LiteralPath $paths.ServerAudit -PathType Leaf) "Xóa cấu hình làm mất audit."
    Assert-Enterprise ($null -eq (Get-ToolEnterpriseServerConfig)) "Cấu hình máy chủ vẫn còn sau khi xóa."
    $resetAuditText = Get-Content -LiteralPath $paths.ServerAudit -Raw
    Assert-Enterprise ($resetAuditText -match 'Server\.ConfigurationResetRequested' -and $resetAuditText -match 'Server\.ConfigurationResetCompleted') "Audit thiếu sự kiện yêu cầu/hoàn tất xóa cấu hình."
    $serverAfterReset = New-ToolEnterpriseServerConfiguration -ServerName "EnterpriseVerificationAfterReset" -AdminCode "Verify-Admin-After-Reset" -BindAddress "127.0.0.1" -Port 49542 -AllowedCidrs @("127.0.0.0/8")
    Assert-Enterprise ([string]$serverAfterReset.ServerName -eq "EnterpriseVerificationAfterReset") "Không tạo lại được máy chủ sau khi xóa cấu hình."

    $catalog = Get-ToolModuleCatalog
    foreach ($moduleId in @("license.manager","license.manager.local","enterprise.server","enterprise.agent")) {
        Assert-Enterprise (@($catalog | Where-Object ModuleId -eq $moduleId).Count -eq 1) "Module contract thiếu $moduleId."
    }
    $managerContract = @($catalog | Where-Object ModuleId -eq "license.manager")[0]
    Assert-Enterprise ([string]$managerContract.NetworkScope -eq "LocalOnly") "Mở Mục 8 phải hoạt động Offline; chỉ tiến trình server/agent mới dùng LAN."
    $launcherText = Get-Content -LiteralPath (Join-Path $SourceDirectory "Tool-Kiem-Tra-v4.8-OneFile.cs") -Raw
    foreach ($mode in @("--enterprise-ui","--enterprise-server","--enterprise-agent","--enterprise-agent-force","--local-license-manager")) {
        Assert-Enterprise ($launcherText.Contains($mode)) "Launcher thiếu mode $mode."
    }
    Assert-Enterprise ($launcherText -notmatch 'mode\s*==\s*LaunchMode\.EnterpriseUi\s*\|\|\s*mode\s*==\s*LaunchMode\.EnterpriseServer') "Launcher vẫn chặn giao diện Mục 8 khi Offline."
    Assert-Enterprise ($launcherText -match 'ResolveEnterpriseNetworkAllowed' -and
        $launcherText -match 'TOOL_ENTERPRISE_NETWORK_ALLOWED' -and
        $launcherText -match 'mode\s*==\s*LaunchMode\.EnterpriseServer\s*\|\|\s*mode\s*==\s*LaunchMode\.EnterpriseAgent') "Launcher không còn chặn riêng tiến trình mạng server/agent theo công tắc Mục 8."
    $dashboardText = Get-Content -LiteralPath (Join-Path $SourceDirectory "Giao-Dien.ps1") -Raw -Encoding UTF8
    Assert-Enterprise ($dashboardText -match 'Start-Process\s+-FilePath\s+\$launcherPath\s+-ArgumentList\s+"--enterprise-ui"' -and
        $dashboardText -match '-File\s+`"\$licenseManagerScript`"' -and
        $dashboardText -notmatch '\$licenseLaunchMode\s*=\s*if\s*\(\$script:offlineMode\)' -and
        $dashboardText -notmatch 'máy chủ/máy trạm bị ẩn') "Dashboard chưa luôn mở đủ trung tâm Mục 8 như v4.2.0.8."
    $enterpriseUiPath = Join-Path $SourceDirectory "enterprise-license-manager.ps1"
    $enterpriseUiText = Get-Content -LiteralPath $enterpriseUiPath -Raw -Encoding UTF8
    Assert-Enterprise ($enterpriseUiText -notmatch '[“”‘’]') "Giao diện enterprise chứa dấu ngoặc kép cong có thể làm PowerShell tách sai tham số."
    Assert-Enterprise ($enterpriseUiText -notmatch '(?<!\$)\(if\s*\(') "Giao diện enterprise chứa biểu thức ngoặc-if không hợp lệ khi chạy; hãy dùng biến trung gian hoặc subexpression PowerShell."
    Assert-Enterprise ($enterpriseUiText -match 'function\s+Fit-EnterpriseWindowToWorkingArea' -and
        $enterpriseUiText -match 'function\s+Update-EnterpriseLayout' -and
        $enterpriseUiText -match 'function\s+Set-EnterpriseAdaptiveButtonRows' -and
        $enterpriseUiText -match 'function\s+Get-EnterpriseClippedButtonLabels' -and
        $enterpriseUiText -match 'AutoScaleMode\]::Dpi' -and
        $enterpriseUiText -match 'HorizontalScroll\.Visible') "Giao diện enterprise thiếu layout thích ứng DPI hoặc kiểm tra chống tràn ngang."
    Assert-Enterprise ($enterpriseUiText -match 'Get-ToolEnterpriseLocalCidrs' -and
        $enterpriseUiText -match '\$script:scanInputBox\.Text\s*=\s*\$input' -and
        $enterpriseUiText -match '\$hostLabel\s*=\s*if\s*\(\$device\.HostName\)' -and
        $enterpriseUiText -match 'enterprise\.server\.scanResultLine' -and
        $enterpriseUiText -match 'enterprise\.server\.scanHostUnknown') "Quét nhanh chưa tự nhận CIDR hoặc hiển thị rõ IP/độ trễ/tên máy."
    Assert-Enterprise ($enterpriseUiText -match 'Get-ToolEnterprisePreferredServerAddress' -and
        $enterpriseUiText -match 'Find-ToolEnterpriseLocalServers' -and
        $enterpriseUiText -match 'enterprise\.client\.discover') "Giao diện chưa tự nhận IP LAN hoặc tự dò máy chủ."
    Assert-Enterprise ($enterpriseUiText -match 'Invoke-ServerDeleteConfiguration' -and
        $enterpriseUiText -match 'enterprise\.server\.delete' -and
        $enterpriseUiText -match 'enterprise\.server\.deletePrompt') "Giao diện thiếu luồng xóa cấu hình có xác nhận."
    Assert-Enterprise ($enterpriseUiText -notmatch 'Mục "Trên máy này"|\$localTab' -and
        $enterpriseUiText -match 'enterprise\.status\.choose' -and
        $enterpriseUiText -match 'enterprise\.local\.tab' -and
        $enterpriseUiText -match '--local-license-manager' -and
        $enterpriseUiText -match 'enterprise\.navigation\.close' -and
        $enterpriseUiText -match 'Invoke-EnterpriseBack' -and
        $enterpriseUiText -match 'RectangleF') "Giao diện mục 8 chưa chuyển sang chọn chức năng hoặc thiếu điều hướng phiên."
    $viCatalog = Get-Content -LiteralPath (Join-Path $SourceDirectory "Tool-Strings.vi-VN.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    $enCatalog = Get-Content -LiteralPath (Join-Path $SourceDirectory "Tool-Strings.en-US.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($preservedKey in @(
        "enterprise.local.tab",
        "enterprise.server.tab",
        "enterprise.client.tab",
        "enterprise.server.create",
        "enterprise.server.pair",
        "enterprise.server.start",
        "enterprise.server.stop",
        "enterprise.server.delete",
        "enterprise.server.firewall",
        "enterprise.server.refresh",
        "enterprise.server.export",
        "enterprise.server.scan",
        "enterprise.server.scanResultLine",
        "enterprise.server.scanHostUnknown",
        "enterprise.server.createJob",
        "enterprise.client.discover",
        "enterprise.client.test",
        "enterprise.client.enroll",
        "enterprise.client.send",
        "enterprise.client.enableAgent",
        "enterprise.client.disableAgent"
    )) {
        Assert-Enterprise ($enterpriseUiText.Contains($preservedKey) -and
            $null -ne $viCatalog.PSObject.Properties[$preservedKey] -and
            $null -ne $enCatalog.PSObject.Properties[$preservedKey]) "Mục 8 làm mất hoặc chưa dịch chức năng: $preservedKey"
    }
    Assert-Enterprise ($enterpriseUiText -match 'function\s+Enable-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'function\s+Disable-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'function\s+Toggle-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'function\s+Confirm-EnterpriseNetworkAccess' -and
        $enterpriseUiText -match 'Set-ToolEnterpriseNetworkAllowedPreference' -and
        $enterpriseUiText -notmatch 'Mục 8 vẫn giữ nguyên đủ 3 chức năng.+v4\.2\.0\.8') "Mục 8 chưa có công tắc mạng bật/tắt riêng hoặc vẫn còn câu cảnh báo cũ."
    Assert-Enterprise ($enterpriseUiText -match 'Tool-UiTheme\.ps1' -and
        $enterpriseUiText -match 'Get-ToolUiTheme' -and
        $enterpriseUiText -match '\$script:enterpriseDark' -and
        $enterpriseUiText -match '\$env:TOOL_UI_THEME\s*=\s*\$script:enterpriseTheme' -and
        $enterpriseUiText -match 'Get-ToolUiContrastRatio') "Chức năng 8 chưa nhận dark mode chung, truyền theme qua UAC hoặc kiểm tra tương phản."
    $localManagerText = Get-Content -LiteralPath (Join-Path $SourceDirectory "windows-office-license-manager.ps1") -Raw -Encoding UTF8
    Assert-Enterprise ($localManagerText -match 'Tool-UiTheme\.ps1' -and
        $localManagerText -match 'Get-ToolUiTheme' -and
        $localManagerText -match 'Set-ToolWindowTheme\s+-Root\s+\$form' -and
        $localManagerText -match 'Get-LocalLicenseText' -and
        $localManagerText -match 'Test-ToolEnterpriseNetworkActionAllowed') "Trình quản lý cục bộ Windows/Office chưa nhận theme, ngôn ngữ hoặc công tắc mạng Mục 8."
    $enterpriseCoreText = Get-Content -LiteralPath (Join-Path $SourceDirectory "Tool-Enterprise.ps1") -Raw -Encoding UTF8
    Assert-Enterprise ($enterpriseCoreText -match 'function\s+Remove-ToolEnterpriseServerConfiguration' -and
        $enterpriseCoreText -match 'Test-ToolEnterpriseAdminCode' -and
        $enterpriseCoreText -match 'PreservedReportsPath') "Lõi enterprise thiếu xóa cấu hình có xác thực/giữ báo cáo."
    Assert-Enterprise ($enterpriseCoreText -match 'function\s+Resolve-ToolEnterpriseServerEndpoint' -and
        $enterpriseCoreText -match 'function\s+Get-ToolEnterpriseConnectionDiagnostic' -and
        $enterpriseCoreText -match 'DiscoveryMethod' -and
        $enterpriseCoreText -match 'ProbePorts' -and
        $enterpriseCoreText -notmatch 'ToolVersionPattern') "Lõi enterprise thiếu IP:cổng, chẩn đoán từng lớp hoặc quét không phụ thuộc ICMP."
    Assert-Enterprise ($enterpriseUiText -match 'ThanhViet Tool v4\.8 Enterprise Agent' -and
        $enterpriseUiText -match 'Enable-EnterpriseServerListenerAccess' -and
        $enterpriseUiText -match 'Resolve-EnterpriseClientServerAddress') "Giao diện enterprise chưa đồng bộ tác vụ v4.8, URLACL/Firewall hoặc tự dò máy chủ."
    Assert-Enterprise ($enterpriseUiText -match 'function\s+Wait-EnterpriseServerReady' -and
        $enterpriseUiText -match 'function\s+Wait-EnterpriseAgentResult' -and
        $enterpriseUiText -match 'ClientAgentResult' -and
        $enterpriseUiText -match 'enterprise\.server\.startingVerified' -and
        $enterpriseUiText -match 'enterprise\.client\.agentSent') 'Giao diện enterprise còn báo thành công trước khi máy chủ/agent có kết quả xác nhận.'
    Assert-Enterprise ($enterpriseUiText -match 'http://\+:\$port/tool/v1/' -and
        $enterpriseUiText -match 'WindowsIdentity.*?User\.Value' -and
        $enterpriseUiText -match 'sddl=D:\(A;;GX;;;\$currentUserSid\)' -and
        $enterpriseUiText -match 'enterprise\.error\.urlAclNotApplied' -and
        $enterpriseUiText -match 'enterprise\.error\.firewallNotApplied') 'URL ACL/Firewall chưa dùng đúng prefix hoặc chưa hậu kiểm quyền listener.'
    $hostPath = Join-Path $SourceDirectory "Tool-EnterpriseHost.ps1"
    $hostText = Get-Content -LiteralPath $hostPath -Raw -Encoding UTF8
    $hostTokens = $null
    $hostParseErrors = $null
    $hostAst = [Management.Automation.Language.Parser]::ParseFile($hostPath, [ref]$hostTokens, [ref]$hostParseErrors)
    Assert-Enterprise (@($hostParseErrors).Count -eq 0) "Tool-EnterpriseHost.ps1 lỗi cú pháp."
    $statusFunction = $hostAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-ToolEnterpriseHostStatus' }, $true)
    Assert-Enterprise ($null -ne $statusFunction) "Thiếu endpoint status tối giản."
    $statusFunctionText = [string]$statusFunction.Extent.Text
    foreach ($requiredField in @('Accepted','ProtocolVersion','ToolVersion')) {
        Assert-Enterprise ($statusFunctionText -match ("(?m)^\s*" + [regex]::Escape($requiredField) + "\s*=")) "Status tối giản thiếu trường $requiredField."
    }
    foreach ($sensitiveField in @('ServerId','ServerName','PreferredAddress','NetworkAddresses','BindAddress','AllowedCidrs','ClientCount','Uptime')) {
        Assert-Enterprise ($statusFunctionText -notmatch ("(?m)^\s*" + [regex]::Escape($sensitiveField) + "\s*=")) "Status không xác thực còn lộ $sensitiveField."
    }
    Assert-Enterprise ($hostText -match 'rate\.Count\+\+' -and $hostText -match 'StatusCode\s+429') "Endpoint Enterprise thiếu rate limit."
    Assert-Enterprise ($hostText -match '\$prefixAddress\s*=\s*if.+?\{\s*"\+"\s*\}' -and $hostText -match 'http://\$prefixAddress') 'Listener không dùng cùng strong-wildcard prefix với URL ACL.'
    $agentText = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-EnterpriseAgent.ps1') -Raw -Encoding UTF8
    Assert-Enterprise ($agentText -match 'function\s+Write-ToolEnterpriseAgentResultFile' -and
        $agentText -match 'ClientAgentResult' -and $agentText -match 'ClientAgentError' -and
        $agentText -match 'Success=\$true; ExitCode=0' -and $agentText -match 'Success=\$false; ExitCode=1') 'Agent chưa ghi kết quả thành công/thất bại có cấu trúc cho giao diện.'
    $previousUiTheme = [string]$env:TOOL_UI_THEME
    try {
        foreach ($networkState in @("0", "1")) {
            $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = $networkState
            foreach ($uiCulture in @("vi-VN", "en-US")) {
                $env:TOOL_UI_CULTURE = $uiCulture
                foreach ($uiTheme in @("Light", "Dark")) {
                    $env:TOOL_UI_THEME = $uiTheme
                    $uiSmokeOutput = @(& $nativePowerShell -NoProfile -ExecutionPolicy RemoteSigned -STA -File $enterpriseUiPath -SmokeTest 2>&1)
                    $uiSmokeExitCode = $LASTEXITCODE
                    Assert-Enterprise ($uiSmokeExitCode -eq 0) "Enterprise UI runtime smoke theme=$uiTheme culture=$uiCulture network=$networkState trả mã ${uiSmokeExitCode}: $($uiSmokeOutput -join '; ')"
                    $expectedNetwork = if ($networkState -eq "1") { "True" } else { "False" }
                    Assert-Enterprise (($uiSmokeOutput -join "`n") -match "ENTERPRISE-UI-SMOKE: PASS \(culture=$uiCulture .*Section8Network=$expectedNetwork.*theme $uiTheme\)") "Enterprise UI smoke không xác nhận theme=$uiTheme, culture=$uiCulture và trạng thái mạng Mục 8."
                }
            }
        }
    } finally {
        $env:TOOL_UI_THEME = $previousUiTheme
    }

    Write-Host "VERIFY-ENTERPRISE: PASS" -ForegroundColor Green
    Write-Host "  Protocol: $($metadata.ProtocolVersion), report schema: $($report.SchemaVersion), module count: $(@($catalog).Count)"
    exit 0
} catch {
    Write-Error "VERIFY-ENTERPRISE: FAIL - $($_.Exception.Message)`n$($_.ScriptStackTrace)"
    exit 1
} finally {
    if ($hostProcess -and -not $hostProcess.HasExited) {
        try {
            $stopPath = Join-Path $testRoot "server\server.stop"
            New-Item -ItemType File -Path $stopPath -Force | Out-Null
            if (-not $hostProcess.WaitForExit(5000)) {
                Stop-Process -Id $hostProcess.Id -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
    if ($hostProcess) { try { $hostProcess.Dispose() } catch {} }
    $env:TOOL_ENTERPRISE_ROOT = $previousRoot
    $env:TOOL_ENTERPRISE_SKIP_ACL = $previousSkipAcl
    $env:TOOL_OFFLINE_MODE = $previousOfflineMode
    $env:TOOL_ENTERPRISE_NETWORK_ALLOWED = $previousEnterpriseNetworkAllowed
    $env:TOOL_ENTERPRISE_NETWORK_SETTINGS_PATH = $previousEnterpriseNetworkSettings
    $env:TOOL_UI_CULTURE = $previousUiCulture
    foreach ($target in @($testRoot,$exportRoot,$separateClientRoot)) {
        try {
            $full = [IO.Path]::GetFullPath($target)
            if ($full.StartsWith($temporaryBase, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $full)) {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}
