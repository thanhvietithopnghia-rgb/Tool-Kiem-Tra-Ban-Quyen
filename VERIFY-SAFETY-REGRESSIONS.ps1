[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$root = [IO.Path]::GetFullPath($SourceDirectory)
$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $failures.Add($Message) }

$policyPath = Join-Path $root 'Tool-SafetyPolicy.ps1'
if (-not (Test-Path -LiteralPath $policyPath -PathType Leaf)) {
    Fail 'Thiếu Tool-SafetyPolicy.ps1.'
} else {
    . $policyPath
}

if (Get-Command Get-ToolSafetyPolicyMetadata -ErrorAction SilentlyContinue) {
    $windowsSpp = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform'
    $officeSpp = 'HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform'
    $licensePolicy = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform'

    if (-not (Test-ToolRegistryValueRestoreAllowed -Path $licensePolicy -ValueName 'NoGenTicket')) { Fail 'NoGenTicket không thể khôi phục tại đúng policy path.' }
    if (-not (Test-ToolRegistryValueRestoreAllowed -Path $windowsSpp -ValueName 'KeyManagementServiceName')) { Fail 'Giá trị KMS Windows hợp lệ bị từ chối.' }
    if (-not (Test-ToolRegistryValueRestoreAllowed -Path $officeSpp -ValueName 'KeyManagementServicePort')) { Fail 'Giá trị KMS Office hợp lệ bị từ chối.' }

    $negativeCases = @(
        @{ Path=$windowsSpp; Name='NoGenTicket' },
        @{ Path=$officeSpp; Name='NoGenTicket' },
        @{ Path=$licensePolicy; Name='KeyManagementServiceName' },
        @{ Path='HKLM:\SOFTWARE\Unrelated'; Name='NoGenTicket' },
        @{ Path=$licensePolicy; Name='Debugger' }
    )
    foreach ($case in $negativeCases) {
        if (Test-ToolRegistryValueRestoreAllowed -Path $case.Path -ValueName $case.Name) {
            Fail "Policy cho phép sai Registry value: $($case.Path) :: $($case.Name)"
        }
    }

    $metadata = Get-ToolSafetyPolicyMetadata
if ([string]$metadata.SchemaVersion -ne '1.0' -or [string]$metadata.ToolVersion -ne '4.8') { Fail 'Metadata safety policy sai phiên bản.' }
    if ([bool]$metadata.StartupTypeChangesAllowedByQuickRepair) { Fail 'Quick repair không được phép đổi StartupType.' }
    $services = @(Get-ToolScanSourceServicePolicy)
    if ($services.Count -ne 3 -or @($services | Where-Object { $_.AllowStartupTypeChange }).Count -ne 0) { Fail 'Service policy không khóa toàn bộ thay đổi StartupType.' }
}

function Read-And-Parse([string]$Name) {
    $path = Join-Path $root $Name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { Fail "Thiếu tệp: $Name"; return '' }
    $tokens = $null
    $parseErrors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "Lỗi cú pháp ${Name}: $($parseError.Message)" }
    return [pscustomobject]@{ Text=(Get-Content -LiteralPath $path -Raw -Encoding UTF8); Ast=$ast }
}

$backup = Read-And-Parse 'windows-license-backup.ps1'
$cleanup = Read-And-Parse 'windows-license-compliance-cleanup.ps1'
$restore = Read-And-Parse 'windows-license-restore.ps1'
$gui = Read-And-Parse 'Giao-Dien.ps1'
$softwareInventory = Read-And-Parse 'Tool-SoftwareInventory.ps1'
$softwareCatalogUpdater = Read-And-Parse 'software-license-online-update.ps1'

if ($backup -and $backup.Text -notmatch 'Backup-RegistryValues\s+\$windowsPolicyPath.+Windows_SPP_Policy') { Fail 'Backup thường chưa lưu riêng policy NoGenTicket bằng RegistryValues.' }
if ($cleanup -and $cleanup.Text -notmatch '(?s)SppNoGenTicketPolicy.+?@\("NoGenTicket"\).+?Type="RegistryValues"') { Fail 'Deep cleanup chưa backup NoGenTicket theo kiểu RegistryValues.' }
if ($restore -and $restore.Text -notmatch 'Test-ToolRegistryValueRestoreAllowed') { Fail 'Restore chưa dùng allowlist theo đúng Registry path/value.' }

foreach ($entry in @($backup, $cleanup, $restore)) {
    if ($entry -and $entry.Text -notmatch 'SafetyPolicySha256') { Fail 'Một luồng backup/restore thiếu hash Tool-SafetyPolicy.ps1.' }
}

if ($cleanup) {
    $repairAst = $cleanup.Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Invoke-ScanSourceRepair' }, $true)
    if (-not $repairAst) {
        Fail 'Không tìm thấy Invoke-ScanSourceRepair.'
    } else {
        $repairText = $repairAst.Extent.Text
        if ($repairText -notmatch 'StartupTypeChanged\s*=\s*\$false') { Fail 'Quick repair không công bố StartupTypeChanged=false.' }
        if ($repairText -notmatch 'RollbackApplied' -or $repairText -notmatch 'Stop-Service') { Fail 'Quick repair thiếu rollback trạng thái service khi recheck thất bại.' }
        if ($repairText -match '(?i)Set-Service\b.+-StartupType|\bconfig\s+\$?\w+\s+start=') { Fail 'Quick repair vẫn thay đổi StartupType.' }
        if ($repairText -notmatch 'StartMode\s*-eq\s*"Disabled"') { Fail 'Quick repair chưa giữ nguyên service Disabled.' }
    }

    $officeParserAst = $cleanup.Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ConvertFrom-OfficeLicenseStatus' }, $true)
    if (-not $officeParserAst) {
        Fail 'Không tìm thấy parser trạng thái nhiều SKU Office.'
    } else {
        try {
            $officeParser = $officeParserAst.Body.GetScriptBlock()
            $officeFixture = @'
---------------------------------------
SKU ID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
LICENSE NAME: Office 16, Office16MondoVL_KMS_Client edition
LICENSE DESCRIPTION: Office 16, VOLUME_KMSCLIENT channel
LICENSE STATUS: ---LICENSED---
Last 5 characters of installed product key: XQBR2
KMS machine registry override defined: 10.20.30.40:1688
---------------------------------------
SKU ID: bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
LICENSE NAME: Office 19, Office19VisioStd2019VL_KMS_Client_AE edition
LICENSE DESCRIPTION: Office 19, VOLUME_KMSCLIENT channel
LICENSE STATUS: ---LICENSED---
Last 5 characters of installed product key: X4VQ2
KMS machine registry override defined: 10.20.30.40:1688
---------------------------------------
SKU ID: cccccccc-cccc-cccc-cccc-cccccccccccc
LICENSE NAME: Office 16, Office16ProjectVL_KMS_Client edition
LICENSE DESCRIPTION: Office 16, VOLUME_KMSCLIENT channel
LICENSE STATUS: ---UNLICENSED---
ERROR CODE: 0xC004F014
---------------------------------------
'@
            $parsedOffice = @(& $officeParser -StatusText $officeFixture -Path 'C:\Office\OSPP.VBS')
            if ($parsedOffice.Count -ne 2) { Fail "Parser Office phải trả đúng 2 SKU KMS đang cấu hình; nhận $($parsedOffice.Count)." }
            if (@($parsedOffice | Where-Object { $_.Last5 -eq 'XQBR2' -and $_.SkuId -eq 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa' }).Count -ne 1) { Fail 'Parser Office bỏ sót SKU KMS thứ nhất.' }
            if (@($parsedOffice | Where-Object { $_.Last5 -eq 'X4VQ2' -and $_.SkuId -eq 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' }).Count -ne 1) { Fail 'Parser Office bỏ sót SKU KMS thứ hai.' }
            if (@($parsedOffice | Where-Object { $_.SkuId -eq 'cccccccc-cccc-cccc-cccc-cccccccccccc' }).Count -ne 0) { Fail 'Parser Office báo nhầm SKU KMS Unlicensed không key/override.' }
        } catch {
            Fail "Không chạy được regression fixture Office nhiều SKU: $($_.Exception.Message)"
        }
    }

    if ($cleanup.Text -notmatch '/dstatusall' -or $cleanup.Text -notmatch 'selectedOfficeTargetIds' -or $cleanup.Text -notmatch 'Get-AllCleanupCandidates') {
        Fail 'Cleanup Office chưa quét /dstatusall, chọn theo SKU hoặc tái tạo danh sách tồn dư sau hậu kiểm.'
    }
    foreach ($requiredToken in @('Get-InstalledSoftwareInventory','Get-ThirdPartyStrongEvidence','Get-ThirdPartyLicenseCandidates','Get-ThirdPartyGenericRemediationPlan','Get-ThirdPartyHostsUpdate','Connect-ThirdPartyApplicationsToCandidates','ThirdPartyLicenseReset','ThirdPartyLicenseState','ThirdPartyUninstallEntry','ThirdPartyHostsEntry','ThirdPartyFirewallBlock','FirewallNotice','RemoveScopedFirewallBlock','ThirdPartyMsiRepair','ThirdPartyMsiUninstall','ThirdPartyOfficialSource','LocalLicenseFileReset','FileArtifact','CleanupFinding','ThirdPartyRemediationFindingCount','SystemChangeCount','ThirdPartyExecutionResults','NoAutomaticChange')) {
        if ($cleanup.Text -notmatch [regex]::Escape($requiredToken)) { Fail "Thiếu thành phần khắc phục phần mềm bên thứ ba: $requiredToken" }
    }
    if ($cleanup.Text -notmatch '(?s)ThirdPartyLicenseState.+?Restorable=\$false' -or $cleanup.Text -notmatch 'selectedVendorScopes') {
        Fail 'Kế hoạch Adobe/Autodesk chưa khóa token activator khỏi restore hoặc chưa xử lý theo phạm vi hãng.'
    }
    foreach ($requiredToken in @('ScanScope','Get-ScopedCleanupCandidates','Test-CleanupScopeReady','restoreBundleReady','backupRequiredBlocked','OperationTimeoutSec 20','OperationTimeoutSec 25')) {
        if ($cleanup.Text -notmatch [regex]::Escape($requiredToken)) { Fail "Luồng theo phạm vi/chống treo/backup fail-closed thiếu: $requiredToken" }
    }
    foreach ($requiredToken in @('Get-ToolSoftwareAssessments','ThirdPartyApplications','ThirdPartyNeedsReviewCount')) {
        if ($cleanup.Text -notmatch [regex]::Escape($requiredToken)) { Fail "Luồng kiểm kê/đánh giá toàn bộ phần mềm thiếu: $requiredToken" }
    }
    if ($cleanup.Text -notmatch 'Get-ToolNativeSystemPath\s+"msiexec\.exe"' -or
        $cleanup.Text -notmatch [regex]::Escape("-Arguments @('/fa', `$productCode, '/qn', '/norestart')") -or
        $cleanup.Text -notmatch [regex]::Escape("-Arguments @('/x', `$productCode, '/qn', '/norestart')") -or
        $cleanup.Text -notmatch [regex]::Escape("Kind='ThirdPartyHostsEntry'; Restorable=`$true")) {
        Fail 'Fallback tổng quát chưa khóa msiexec vào đường dẫn hệ thống/product code hoặc chưa cho phép hoàn tác hosts.'
    }
    if ($cleanup.Text -notmatch '\$decisive\s*=\s*\[bool\]\(-not \$FolderOnly -and \$KnownSpecific -and \$Active\)' -or
        $cleanup.Text -notmatch 'GetExtension\(\$text\).+?\.exe.+?\.jar' -or
        $cleanup.Text -notmatch 'isBroadRoot') {
        Fail 'Tương quan bằng chứng tổng quát thiếu chặn tên đang hoạt động không đặc hiệu, phần mở rộng tài liệu hoặc install root quá rộng.'
    }

    try {
        function Import-CleanupFunctionForFixture([string]$Name) {
            $functionAst = $cleanup.Ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $Name
            }, $true)
            if (-not $functionAst) { throw "Missing function: $Name" }
            Invoke-Expression ("function script:" + $Name + " " + $functionAst.Body.Extent.Text)
        }
        function Get-CleanupText { param([string]$Key, [object[]]$Arguments=@()); return ($Key + ':' + (@($Arguments) -join '|')) }
        foreach ($name in @('Get-ThirdPartyNormalizedInstallRoot','Get-ThirdPartyMsiProductCode','Test-ThirdPartyArtifactPath','Test-ThirdPartyApplicationPathScope','Get-ThirdPartyHostsUpdate','Get-ThirdPartyGenericRemediationPlan','Get-ThirdPartyLicenseCandidates','New-CleanupItem','Expand-SelectedCleanupCandidates','Get-DryRunRemediationPlan','Add-ThirdPartyVerification','Test-CleanupScopeReady')) {
            Import-CleanupFunctionForFixture $name
        }
        $broadRootFixture = [pscustomobject]@{ InstallLocation=$env:ProgramFiles; RepresentativePath='' }
        if (-not [string]::IsNullOrWhiteSpace((Get-ThirdPartyNormalizedInstallRoot -Application $broadRootFixture))) {
            Fail 'Install root tổng quát Program Files vẫn được dùng để gắn bằng chứng giữa các ứng dụng không liên quan.'
        }
        $scopedRootFixture = [pscustomobject]@{ InstallLocation=(Join-Path $env:ProgramFiles 'Example Fixture App'); RepresentativePath='' }
        if ((Get-ThirdPartyNormalizedInstallRoot -Application $scopedRootFixture) -notmatch '(?i)Example Fixture App$') {
            Fail 'Install root riêng của ứng dụng bị loại bỏ nhầm.'
        }
        $hostsFixture = Get-ThirdPartyHostsUpdate -Lines @(
            '# keep comment',
            '0.0.0.0 license.example.test other.example.test # mixed',
            '127.0.0.1 LICENSE.EXAMPLE.TEST',
            '192.168.1.10 intranet.example.test'
        ) -Targets @('license.example.test')
        if ([int]$hostsFixture.RemovedCount -ne 2 -or [int]$hostsFixture.TargetCount -ne 1 -or
            (@($hostsFixture.Lines) -join "`n") -notmatch 'other\.example\.test' -or
            (@($hostsFixture.Lines) -join "`n") -notmatch '192\.168\.1\.10 intranet\.example\.test' -or
            (@($hostsFixture.Lines) -join "`n") -match '(?im)^\s*(?:0\.0\.0\.0|127\.0\.0\.1)\s+license\.example\.test') {
            Fail 'Fixture hosts chưa gỡ đúng domain đích hoặc đã làm mất mục không liên quan.'
        }
        $artifactFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-ThirdParty-Rescan-Fixture-' + [guid]::NewGuid().ToString('N'))
        $previousToolDataRoot = [string]$env:TOOL_DATA_ROOT
        try {
            $artifactInstallRoot = Join-Path $artifactFixtureRoot 'ExampleApp'
            [void][IO.Directory]::CreateDirectory($artifactInstallRoot)
            $firewallApplicationPath = Join-Path $artifactInstallRoot 'Example.exe'
            [IO.File]::WriteAllText($firewallApplicationPath, 'fixture-only', (New-Object Text.UTF8Encoding($false)))
            $artifactPath = Join-Path $artifactFixtureRoot 'license-crack.zip'
            [IO.File]::WriteAllText($artifactPath, 'fixture-only', (New-Object Text.UTF8Encoding($false)))
            $artifactApp = [pscustomobject]@{
                Id='artifact-app'; Name='Example Pro'; SourceKind='Registry'; Publisher='Example'; VendorScope='Example'
                InstallLocation=$artifactInstallRoot; RepresentativePath=''; RegistryPath=''; UninstallString=''
                ManualEligible=$true; AutoEligible=$false; RemediationAdapter='Generic'; OfficialReferenceUrl='https://example.invalid/'
                Evidence=@([pscustomobject]@{ Code='SuspiciousActivatorFileArtifact'; Source='FileArtifact'; Detail=$artifactPath; Strength='Moderate'; Decisive=$false })
            }
            if (-not (Test-ThirdPartyArtifactPath -Path $artifactPath -Applications @($artifactApp) -AllowUserArtifactRoots)) {
                Fail 'Tệp activator chính xác trong vùng người dùng không được chấp nhận vào kế hoạch cách ly.'
            }
            $artifactPlan = @(Get-ThirdPartyGenericRemediationPlan -Applications @($artifactApp))
            if (@($artifactPlan | Where-Object { $_.Type -eq 'File' -and $_.Kind -eq 'ThirdPartyUnauthorizedArtifact' -and $_.Location -eq $artifactPath }).Count -ne 1) {
                Fail 'FileArtifact phát hiện trong Downloads/TEMP chưa được chuyển thành hành động cách ly chính xác.'
            }
            $firewallApp = [pscustomobject]@{
                Id='firewall-app'; Name='Firewall Fixture'; SourceKind='Registry'; Publisher='Example'; VendorScope='Example'
                InstallLocation=$artifactInstallRoot; RepresentativePath=$firewallApplicationPath; RegistryPath=''; UninstallString=''
                ManualEligible=$true; AutoEligible=$true; RemediationAdapter='Generic'; OfficialReferenceUrl='https://example.invalid/'
                Evidence=@(
                    [pscustomobject]@{ Code='KnownUnauthorizedName'; Source='Identity'; Detail='fixture activator'; Strength='Strong'; Decisive=$true },
                    [pscustomobject]@{ Code='LicenseDomainBlocked'; Source='Hosts'; Detail='license.example.test'; Strength='Moderate'; Decisive=$false },
                    [pscustomobject]@{ Code='ApplicationOutboundBlocked'; Source='Firewall'; Detail=('Fixture outbound block | ' + $firewallApplicationPath); Strength='Moderate'; Decisive=$false }
                )
            }
            $firewallPlan = @(Get-ThirdPartyGenericRemediationPlan -Applications @($firewallApp))
            if (@($firewallPlan | Where-Object { $_.Type -eq 'Firewall' -and $_.Kind -eq 'ThirdPartyFirewallBlock' -and $_.Location -eq $firewallApplicationPath -and -not [bool]$_.Restorable }).Count -ne 1) {
                Fail 'Quy tắc Firewall outbound-block đúng đường dẫn ứng dụng chưa vào kế hoạch thủ công.'
            }
            $firewallCandidate = @(Get-ThirdPartyLicenseCandidates -Applications @($firewallApp) -Evidence @())
            if ($firewallCandidate.Count -ne 1 -or [bool]$firewallCandidate[0].AutoEligible -or
                @($firewallCandidate[0].PlanItems | Where-Object { $_.Type -eq 'Hosts' }).Count -ne 1 -or
                @($firewallCandidate[0].PlanItems | Where-Object { $_.Type -eq 'Firewall' }).Count -ne 1) {
                Fail 'Candidate có Firewall không giữ manual-only hoặc thiếu hành động hosts/Firewall chính xác.'
            }
            $standaloneEvidence = [pscustomobject]@{
                Code='UncorrelatedFileArtifact'; Type='FileArtifact'; Source='FileArtifact'; Name='license-crack.zip'
                Location=$artifactPath; ApplicationId=''; VendorScope='Uncorrelated'; Strength='Moderate'
                EvidenceGroup='ActivatorArtifact'; Decisive=$false; Detail='fixture'
            }
            $standaloneCandidates = @(Get-ThirdPartyLicenseCandidates -Applications @() -Evidence @($standaloneEvidence))
            if ($standaloneCandidates.Count -ne 1 -or @($standaloneCandidates[0].ApplicationIds).Count -ne 0 -or
                @($standaloneCandidates[0].PlanItems | Where-Object { $_.Type -eq 'File' -and $_.Location -eq $artifactPath }).Count -ne 1) {
                Fail 'Tệp activator độc lập không tương quan ứng dụng chưa tạo candidate chọn thủ công.'
            }
            $env:TOOL_DATA_ROOT = Join-Path $artifactFixtureRoot 'ToolData'
            $backupArtifactRoot = Join-Path $env:TOOL_DATA_ROOT 'backups\quarantine_fixture'
            [void][IO.Directory]::CreateDirectory($backupArtifactRoot)
            $backupArtifact = Join-Path $backupArtifactRoot 'license-crack.zip'
            [IO.File]::WriteAllText($backupArtifact, 'fixture-only', (New-Object Text.UTF8Encoding($false)))
            if (Test-ThirdPartyArtifactPath -Path $backupArtifact -Applications @($artifactApp) -AllowUserArtifactRoots) {
                Fail 'Tệp trong kho backup/quarantine đang bị đưa ngược vào kế hoạch làm sạch.'
            }
        } finally {
            $env:TOOL_DATA_ROOT = $previousToolDataRoot
            if (Test-Path -LiteralPath $artifactFixtureRoot) { Remove-Item -LiteralPath $artifactFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }
        }

        $verificationFixture = [pscustomobject]@{
            ScanWarningCount=0; ThirdPartyCandidateCount=0; ReadyForOfficialActivation=$true
            Conclusion=''; HandlingGuidance=@(); ReadinessChecks=@(); ScopeNote=''
        }
        $verificationFixture = Add-ThirdPartyVerification -Verification $verificationFixture -ThirdPartyCandidates @() -ThirdPartyApplications @(
            [pscustomobject]@{ AssessmentCode='Unverified'; NeedsReview=$true; CleanupFinding=$false; RemediationSupported=$false }
        )
        if ([int]$verificationFixture.ThirdPartyNeedsReviewCount -ne 1 -or
            [int]$verificationFixture.ThirdPartyRemediationFindingCount -ne 0 -or
            -not [bool]$verificationFixture.ReadyForOfficialActivation -or
            -not (Test-CleanupScopeReady -Verification $verificationFixture -Scope ThirdParty)) {
            Fail 'Phần mềm chỉ Chưa xác minh vẫn chặn hậu kiểm hoặc quay lại hàng đợi làm sạch.'
        }
        $standaloneVerificationFixture = [pscustomobject]@{
            ScanWarningCount=0; ThirdPartyCandidateCount=0; ReadyForOfficialActivation=$true
            Conclusion=''; HandlingGuidance=@(); ReadinessChecks=@(); ScopeNote=''
        }
        $standaloneVerificationFixture = Add-ThirdPartyVerification -Verification $standaloneVerificationFixture `
            -ThirdPartyCandidates @($standaloneCandidates) -ThirdPartyApplications @()
        if ([int]$standaloneVerificationFixture.ThirdPartyRemediationFindingCount -ne 1 -or
            [bool]$standaloneVerificationFixture.ReadyForOfficialActivation -or
            (Test-CleanupScopeReady -Verification $standaloneVerificationFixture -Scope ThirdParty)) {
            Fail 'Candidate tệp activator độc lập không chặn hậu kiểm trước khi được cách ly.'
        }
        $abbyyGuid = '{CEEB2A9C-3D5F-4E95-90BD-7EB73650105C}'
        $abbyyEvidence = @([pscustomobject]@{ Code='KnownUnauthorizedName'; Source='Identity'; Detail='by sandyd'; Strength='Strong' })
        $abbyyApps = @(
            [pscustomobject]@{ Id='abbyy-shortcut'; Name='ABBYY FineReader'; SourceKind='Shortcut'; Publisher='ABBYY'; VendorScope='ABBYY'; InstallLocation='C:\Program Files\ABBYY FineReader 16'; RepresentativePath='C:\Program Files\ABBYY FineReader 16\HotFolder.exe'; RegistryPath=''; UninstallString=''; ManualEligible=$true; AutoEligible=$true; RemediationAdapter='Generic'; OfficialReferenceUrl='https://pdf.abbyy.com/finereader-pdf/'; Evidence=@([pscustomobject]@{ Code='SignatureHashMismatch'; Source='Authenticode'; Detail='C:\Program Files\ABBYY FineReader 16\HotFolder.exe'; Strength='Strong' }) },
            [pscustomobject]@{ Id='abbyy-registry'; Name='ABBYY FineReader PDF by sandyd'; SourceKind='Registry'; Publisher='ABBYY'; VendorScope='ABBYY'; InstallLocation='C:\Program Files\ABBYY FineReader 16'; RepresentativePath='C:\Program Files\ABBYY FineReader 16\FineReader.exe'; RegistryPath=('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + $abbyyGuid); UninstallString=('MsiExec.exe /I' + $abbyyGuid); ManualEligible=$true; AutoEligible=$true; RemediationAdapter='Generic'; OfficialReferenceUrl='https://pdf.abbyy.com/finereader-pdf/'; Evidence=$abbyyEvidence }
        )
        $candidates = @(Get-ThirdPartyLicenseCandidates -Applications $abbyyApps -Evidence @())
        if ($candidates.Count -ne 1 -or [string]$candidates[0].RemediationMode -ne 'ManualOfficialReinstall' -or [bool]$candidates[0].AutoEligible -or @($candidates[0].ApplicationIds).Count -ne 2) {
            Fail 'Fixture ABBYY chưa được gom thành một candidate chọn thủ công, không tự gỡ.'
        }
        if (@($candidates[0].PlanItems | Where-Object { $_.Type -eq 'Uninstall' -and $_.Kind -eq 'ThirdPartyMsiUninstall' -and $_.Location -eq $abbyyGuid }).Count -ne 1) {
            Fail 'Fixture ABBYY thiếu fallback gỡ MSI bằng product code đã xác thực.'
        }

        $repairGuid = '{11111111-2222-3333-4444-555555555555}'
        $repairApp = [pscustomobject]@{ Id='example-pro'; Name='Example Pro'; SourceKind='Registry'; Publisher='Example'; VendorScope='Example'; InstallLocation='C:\Program Files\Example Pro'; RepresentativePath='C:\Program Files\Example Pro\Example.exe'; RegistryPath=('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + $repairGuid); UninstallString=('MsiExec.exe /I' + $repairGuid); ManualEligible=$true; AutoEligible=$true; RemediationAdapter='Generic'; OfficialReferenceUrl='https://example.invalid/'; Evidence=@([pscustomobject]@{ Code='SignatureHashMismatch'; Source='Authenticode'; Detail='C:\Program Files\Example Pro\Example.exe'; Strength='Strong' }) }
        $repairCandidate = @(Get-ThirdPartyLicenseCandidates -Applications @($repairApp) -Evidence @())
        if ($repairCandidate.Count -ne 1 -or -not [bool]$repairCandidate[0].AutoEligible -or [string]$repairCandidate[0].RemediationMode -ne 'AutomaticOfficialRepair' -or @($repairCandidate[0].PlanItems | Where-Object { $_.Type -eq 'Repair' -and $_.Location -eq $repairGuid }).Count -ne 1) {
            Fail 'Fixture MSI bị sửa chưa tạo đúng kế hoạch Repair tự động an toàn.'
        }

        $dryRunAst = $cleanup.Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-DryRunRemediationPlan'
        }, $true)
        $mutatingCommands = @($dryRunAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            [string]$node.GetCommandName() -in @('Remove-Item','Move-Item','Copy-Item','Set-Item','Set-ItemProperty','New-ItemProperty','Remove-ItemProperty','Stop-Process','Stop-Service','Set-Service','Start-Process','Checkpoint-Computer','Invoke-WebRequest','Invoke-RestMethod')
        }, $true))
        if ($mutatingCommands.Count -ne 0) { Fail 'Bộ lập kế hoạch Dry Run chứa lệnh thay đổi hệ thống hoặc mạng.' }
        $script:releaseVersion = '4.6.2.0'
        $dryRunCandidate = New-CleanupItem -Type 'File' -Kind 'HookFile' -Name 'fixture.dll' -Location 'C:\Fixture\fixture.dll' -Detail 'fixture'
        $dryRunPlan = @(Get-DryRunRemediationPlan -Candidates @($dryRunCandidate) -SelectedIds @([string]$dryRunCandidate.Id))
        if ($dryRunPlan.Count -ne 3 -or
            @($dryRunPlan | Where-Object { $_.ActionCode -eq 'CreateRestorePoint' }).Count -ne 1 -or
            @($dryRunPlan | Where-Object { $_.ActionCode -eq 'CreateSignedBackup' }).Count -ne 1 -or
            @($dryRunPlan | Where-Object { $_.ActionCode -eq 'QuarantineFile' -and $_.Target -eq 'C:\Fixture\fixture.dll' }).Count -ne 1) {
            Fail 'Dry Run chưa lập đúng kế hoạch restore point/backup/hành động chi tiết.'
        }
        $dryRunFirewallCandidate = New-CleanupItem -Type 'Firewall' -Kind 'ThirdPartyFirewallBlock' -Name 'Fixture outbound block' -Location 'C:\Fixture\Example.exe' -Detail 'fixture'
        $dryRunFirewallPlan = @(Get-DryRunRemediationPlan -Candidates @($dryRunFirewallCandidate) -SelectedIds @([string]$dryRunFirewallCandidate.Id))
        if ($dryRunFirewallPlan.Count -ne 3 -or
            @($dryRunFirewallPlan | Where-Object { $_.ActionCode -eq 'RemoveScopedFirewallBlock' -and -not [bool]$_.Restorable }).Count -ne 1) {
            Fail 'Dry Run chưa công bố đúng hành động Firewall manual-only, không tự khôi phục.'
        }
    } catch {
        Fail "Không chạy được fixture khắc phục tổng quát/ABBYY: $($_.Exception.Message)"
    }
}

if ($gui) {
    $integrityGuardAst = $gui.Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Confirm-IntegrityForElevatedAction' }, $true)
    if (-not $integrityGuardAst) {
        Fail 'Không tìm thấy bộ khóa toàn vẹn cho thao tác quản trị.'
    } else {
        $previousSecureLaunch = [string]$env:TOOL_SECURE_LAUNCH
        $previousRuntimeFailed = [string]$env:TOOL_SECURE_RUNTIME_FAILED
        try {
            Invoke-Expression ("function script:Confirm-IntegrityForElevatedAction " + $integrityGuardAst.Body.Extent.Text)
            function script:Test-ProtectedToolDirectoryAcl { param([string]$path); return $true }
            function script:Test-ToolIntegrity { return [pscustomobject]@{ Valid=$true; Message='fixture-valid' } }
            $script:baseDir = 'fixture-base'
            $script:runtimeDir = 'fixture-runtime'
            $env:TOOL_SECURE_LAUNCH = '1'
            $env:TOOL_SECURE_RUNTIME_FAILED = '1'
            if (-not (Confirm-IntegrityForElevatedAction 'fixture-action')) {
                Fail 'Cờ lỗi ACL lịch sử vẫn chặn thao tác dù ACL hiện tại đã được xác thực an toàn.'
            }
            if ([string]$env:TOOL_SECURE_RUNTIME_FAILED -ne '0') {
                Fail 'Cờ lỗi ACL lịch sử không được xóa sau khi xác thực lại ACL hiện tại.'
            }
        } catch {
            Fail "Không chạy được fixture chống chặn nhầm ACL runtime: $($_.Exception.Message)"
        } finally {
            $env:TOOL_SECURE_LAUNCH = $previousSecureLaunch
            $env:TOOL_SECURE_RUNTIME_FAILED = $previousRuntimeFailed
        }
    }
    $autoSafeAst = $gui.Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-AutomaticSafeCleanupItems' }, $true)
    if (-not $autoSafeAst) {
        Fail 'Không tìm thấy bộ lọc tự động làm sạch an toàn.'
    } else {
        try {
            $autoSafeFilter = $autoSafeAst.Body.GetScriptBlock()
            $autoFixture = @(
                [pscustomobject]@{ Id='win-kms'; Type='Registry'; Kind='KmsOverride'; Location=$windowsSpp },
                [pscustomobject]@{ Id='office-kms'; Type='Registry'; Kind='KmsOverride'; Location=$officeSpp },
                [pscustomobject]@{ Id='nogen'; Type='Registry'; Kind='SppNoGenTicketPolicy'; Location=$licensePolicy },
                [pscustomobject]@{ Id='wrong-path'; Type='Registry'; Kind='KmsOverride'; Location='HKLM:\SOFTWARE\Unrelated' },
                [pscustomobject]@{ Id='license'; Type='License'; Kind='WindowsKmsLicense'; Location='KMS=example' },
                [pscustomobject]@{ Id='file'; Type='File'; Kind='HookFile'; Location='C:\Windows\System32\SppExtComObjHook.dll' },
                [pscustomobject]@{ Id='history'; Type='History'; Kind='DefenderEvent'; Location='Event 1116' },
                [pscustomobject]@{ Id='adobe-auto'; Type='Application'; Kind='ThirdPartyLicenseReset'; Location='Adobe'; AutoEligible=$true },
                [pscustomobject]@{ Id='generic-repair-auto'; Type='Application'; Kind='ThirdPartyLicenseReset'; Location='Example'; AutoEligible=$true },
                [pscustomobject]@{ Id='generic-uninstall-manual'; Type='Application'; Kind='ThirdPartyLicenseReset'; Location='ABBYY'; AutoEligible=$false },
                [pscustomobject]@{ Id='autodesk-review'; Type='Application'; Kind='ThirdPartyLicenseReset'; Location='Autodesk'; AutoEligible=$false }
            )
            $autoSelected = @(& $autoSafeFilter -CleanupItems $autoFixture)
            $autoIds = @($autoSelected | ForEach-Object { [string]$_.Id })
            if ($autoSelected.Count -ne 5 -or $autoIds -notcontains 'win-kms' -or $autoIds -notcontains 'office-kms' -or $autoIds -notcontains 'nogen' -or $autoIds -notcontains 'adobe-auto' -or $autoIds -notcontains 'generic-repair-auto') {
                Fail 'Bộ lọc tự động không chọn đúng Registry allowlist và ứng dụng đã đủ điều kiện.'
            }
            if ($autoIds -contains 'wrong-path' -or $autoIds -contains 'license' -or $autoIds -contains 'file' -or $autoIds -contains 'history' -or $autoIds -contains 'generic-uninstall-manual' -or $autoIds -contains 'autodesk-review') {
                Fail 'Bộ lọc tự động đã chọn mục ngoài allowlist hoặc ứng dụng chưa đủ điều kiện.'
            }
        } catch {
            Fail "Không chạy được fixture tự động làm sạch an toàn: $($_.Exception.Message)"
        }
    }
    if ($gui.Text -notmatch 'Start-CleanupDeep\s+-CleanupItems.+-AutomaticSafeMode' -or $gui.Text -notmatch 'Confirm-AutomaticSafeCleanup') {
        Fail 'Luồng tự động chưa bắt buộc xem trước/xác nhận bằng bộ lọc an toàn.'
    }
    foreach ($requiredToken in @('Show-LicenseScopeChooser','cleanup.scope.scanAll','cleanup.scope.scanWindowsOffice','cleanup.scope.scanThirdParty','Start-CleanupBackup -Scope $selectedScope','Start-CleanupRestore -Scope $selectedScope','cleanup.report.readyOnDemand','progress.slowTask')) {
        if ($gui.Text -notmatch [regex]::Escape($requiredToken)) { Fail "GUI thiếu luồng phạm vi hoặc bảo vệ chống treo: $requiredToken" }
    }
    foreach ($requiredToken in @('Show-ThirdPartyAssessmentResults','Get-GuiThirdPartyCleanupFindings','Get-GuiThirdPartyStandaloneCleanupRows','ThirdPartyRemediationFindingCount','software.online.button','Start-SoftwareCatalogOnlineUpdate','status.chooseTask')) {
        if ($gui.Text -notmatch [regex]::Escape($requiredToken)) { Fail "GUI thiếu kết quả phần mềm/Kết nối online/trạng thái ban đầu: $requiredToken" }
    }
    try {
        foreach ($functionName in @('Test-GuiThirdPartyCleanupFinding','Get-GuiThirdPartyCleanupFindings','Get-GuiThirdPartyStandaloneCleanupRows')) {
            $functionAst = $gui.Ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
            }, $true)
            if (-not $functionAst) { throw "Missing function: $functionName" }
            Invoke-Expression ("function script:" + $functionName + " " + $functionAst.Body.Extent.Text)
        }
        function script:Get-DashboardText { param([string]$Key, [object[]]$Arguments=@()); return $Key }
        $visibleCleanupFindings = @(Get-GuiThirdPartyCleanupFindings -Applications @(
            [pscustomobject]@{ Name='Cleaned App'; AssessmentCode='Unverified'; NeedsReview=$true; CleanupFinding=$false },
            [pscustomobject]@{ Name='Residual App'; AssessmentCode='Suspicious'; NeedsReview=$true; CleanupFinding=$true }
        ))
        if ($visibleCleanupFindings.Count -ne 1 -or [string]$visibleCleanupFindings[0].Name -ne 'Residual App') {
            Fail 'GUI vẫn đưa phần mềm đã sạch bằng chứng quay lại danh sách làm sạch sau quét lại.'
        }
        $standaloneRows = @(Get-GuiThirdPartyStandaloneCleanupRows -Candidates @([pscustomobject]@{
            Id='standalone-file'; Name='license-crack.zip'; ApplicationIds=@(); RemediationMode='ArtifactCleanup'
            Evidence=@([pscustomobject]@{ Code='UncorrelatedFileArtifact'; Location='C:\Fixture\license-crack.zip' })
            PlanItems=@([pscustomobject]@{ Type='File'; Kind='ThirdPartyUnauthorizedArtifact' })
        }))
        if ($standaloneRows.Count -ne 1 -or -not [bool]$standaloneRows[0].CleanupFinding -or [string]$standaloneRows[0].CleanupCandidateId -ne 'standalone-file') {
            Fail 'GUI không hiển thị candidate tệp activator độc lập để người dùng chọn cách ly.'
        }
    } catch {
        Fail "Không chạy được fixture lọc danh sách làm sạch sau quét lại: $($_.Exception.Message)"
    }
}

if ($softwareInventory) {
    foreach ($requiredToken in @('Get-ToolSoftwareInventory','Get-ToolSoftwareAssessments','Get-ToolSoftwareKnownActivationState','Get-ToolSoftwareDeepScanEvidence','Get-ToolSoftwareDeepSystemSnapshot','Get-ToolSoftwareLastDeepScanMetadata','Merge-ToolSoftwareInventoryRecords','Test-ToolSoftwareLikelySystemComponent','CleanupFinding','RemediationEvidenceCount','IsSystemComponent','KnownBadFileHash','DeepSignatureHashMismatch','Update-ToolSoftwareLicenseCatalog','Explicit user consent is required','raw.githubusercontent.com','Catalog URL is outside the HTTPS allowlist',"`$request.Method = 'GET'",'AllowAutoRedirect = $false','ContentLength -gt 2097152','UploadedInventory=$false','SentLicenseKeys=$false')) {
        if ($softwareInventory.Text -notmatch [regex]::Escape($requiredToken)) { Fail "Mô-đun kiểm kê/danh mục online thiếu ràng buộc an toàn: $requiredToken" }
    }
    if ($softwareInventory.Text -match '(?i)\b(method\s*=\s*["''](?:POST|PUT|PATCH)|uploadfile|invoke-restmethod\b.+-(?:method\s+)?(?:post|put|patch))') {
        Fail 'Mô-đun danh mục phần mềm chứa phương thức tải dữ liệu lên.'
    }
    try {
        . (Join-Path $root 'Tool-SoftwareInventory.ps1')
        foreach ($dateFixture in @(
            [pscustomobject]@{ Raw='20260811'; Expected='2026-08-11' },
            [pscustomobject]@{ Raw='20260811112233.000000+420'; Expected='2026-08-11' },
            [pscustomobject]@{ Raw='1786406400'; Expected='2026-08-11' }
        )) {
            if ((ConvertTo-ToolSoftwareInstallDateText $dateFixture.Raw) -ne $dateFixture.Expected) {
                Fail "Ngày cài '$($dateFixture.Raw)' chưa chuẩn hóa thành $($dateFixture.Expected)."
            }
        }
        foreach ($activatorFixture in @('TSforge Activation','Office OHook','MAS_AIO','KMS_VL_ALL','Microsoft Toolkit')) {
            if ($activatorFixture -notmatch $script:ToolSoftwareKnownActivatorPattern) { Fail "Thiếu mẫu activator: $activatorFixture" }
        }
        if ('Microsoft.Toolkit.Win32.UI.XamlHost.dll' -match $script:ToolSoftwareKnownActivatorPattern) {
            Fail 'Thư viện Microsoft.Toolkit hợp lệ đang bị nhầm với Microsoft Toolkit activator.'
        }
        if ('IObit Unlocker' -match $script:ToolSoftwareSuspiciousArtifactPattern) {
            Fail 'Tên sản phẩm hợp lệ IObit Unlocker bị coi nhầm là artifact crack.'
        }
        if ('iManage.WorkOfficeAddIn.Patcher.dll' -match $script:ToolSoftwareSuspiciousArtifactPattern) {
            Fail 'DLL Patcher hợp lệ không có ngữ cảnh license/activation bị coi nhầm là artifact crack.'
        }
        if ('license-crack.ps1' -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) {
            Fail 'Mẫu artifact crack tổng quát không còn được nhận diện.'
        }
        if ('license-patcher.exe' -notmatch $script:ToolSoftwareSuspiciousArtifactPattern) {
            Fail 'Mẫu license patcher có ngữ cảnh không còn được nhận diện.'
        }
        $fixtureCatalog = [pscustomobject]@{
            CatalogSource='Fixture'; CatalogVersion='1.0.0.0'; Products=@([pscustomobject]@{
                Id='abbyy-fixture'; Vendor='ABBYY'; NamePatterns=@('(?i)ABBYY.*FineReader'); PublisherPatterns=@('(?i)ABBYY')
                LicenseModel='Paid'; OfficialUrl='https://pdf.abbyy.com/finereader-pdf/'; LicenseDomains=@(); UnauthorizedNamePatterns=@('(?i)by\s+sandy[d]?')
            })
        }
        $fixtureApp = [pscustomobject]@{
            Id='abbyy-fixture'; Name='ABBYY FineReader PDF by sandyd'; Version='16'; Publisher='ABBYY Development, Inc.'
            InstallLocation=''; RepresentativePath=''; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false
        }
        $assessment = @(Get-ToolSoftwareAssessments -Applications @($fixtureApp) -Catalog $fixtureCatalog)
        if ($assessment.Count -ne 1 -or [string]$assessment[0].AssessmentCode -ne 'NonGenuine' -or -not [bool]$assessment[0].ManualEligible -or [string]$assessment[0].RemediationAdapter -ne 'Generic') {
            Fail 'Đánh giá ABBYY tổng quát chưa mở chọn thủ công từ bằng chứng mạnh.'
        }
    } catch {
        Fail "Không chạy được fixture đánh giá ABBYY: $($_.Exception.Message)"
    }
    $rescanFixtureRoot = ''
    try {
        $rescanFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-ThirdParty-EndToEnd-Fixture-' + [guid]::NewGuid().ToString('N'))
        $rescanInstallRoot = Join-Path $rescanFixtureRoot 'ExampleApp'
        [void][IO.Directory]::CreateDirectory($rescanInstallRoot)
        $rescanArtifact = Join-Path $rescanFixtureRoot 'license-crack.zip'
        [IO.File]::WriteAllText($rescanArtifact, 'fixture-only', (New-Object Text.UTF8Encoding($false)))
        $rescanCatalog = [pscustomobject]@{
            CatalogSource='Fixture'; CatalogVersion='1.0.0.0'; Products=@([pscustomobject]@{
                Id='rescan-fixture'; Vendor='Example'; NamePatterns=@('^Rescan Fixture$'); PublisherPatterns=@('^Example$')
                LicenseModel='Paid'; OfficialUrl='https://example.invalid/'; LicenseDomains=@(); UnauthorizedNamePatterns=@()
            })
        }
        $rescanApp = [pscustomobject]@{
            Id='rescan-app'; Name='Rescan Fixture'; Version='1'; Publisher='Example'; InstallLocation=$rescanInstallRoot
            RepresentativePath=''; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false
            RegistryPath=''; UninstallString=''
        }
        $rescanEvidence = [pscustomobject]@{
            Code='SuspiciousActivatorFileArtifact'; Type='FileArtifact'; Source='FileArtifact'; Name='license-crack.zip'
            Location=$rescanArtifact; ApplicationId='rescan-app'; VendorScope='Example'; Strength='Moderate'
            EvidenceGroup='ActivatorArtifact'; Decisive=$false; Detail='fixture'
        }
        $beforeCleanup = @(Get-ToolSoftwareAssessments -Applications @($rescanApp) -Catalog $rescanCatalog -ExternalEvidence @($rescanEvidence))[0]
        $beforeCandidates = @(Get-ThirdPartyLicenseCandidates -Applications @($beforeCleanup) -Evidence @($rescanEvidence))
        if (-not [bool]$beforeCleanup.CleanupFinding -or $beforeCandidates.Count -ne 1 -or
            @($beforeCandidates[0].PlanItems | Where-Object { $_.Type -eq 'File' -and $_.Location -eq $rescanArtifact }).Count -ne 1) {
            Fail 'Fixture trước làm sạch chưa tạo đúng finding/candidate cho FileArtifact.'
        }
        [IO.File]::Delete($rescanArtifact)
        $afterCleanup = @(Get-ToolSoftwareAssessments -Applications @($rescanApp) -Catalog $rescanCatalog -ExternalEvidence @())[0]
        $afterCandidates = @(Get-ThirdPartyLicenseCandidates -Applications @($afterCleanup) -Evidence @())
        $afterVisible = @(Get-GuiThirdPartyCleanupFindings -Applications @($afterCleanup))
        if ([bool]$afterCleanup.CleanupFinding -or $afterCandidates.Count -ne 0 -or $afterVisible.Count -ne 0) {
            Fail 'Fixture end-to-end: làm sạch xong quét lại vẫn còn trong hàng đợi phần mềm khác.'
        }
    } catch {
        Fail "Không chạy được fixture end-to-end làm sạch/quét lại phần mềm khác: $($_.Exception.Message)"
    } finally {
        if ($rescanFixtureRoot -and (Test-Path -LiteralPath $rescanFixtureRoot)) { Remove-Item -LiteralPath $rescanFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }
    $deepFixtureRoot = ''
    try {
        $deepFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-Software-DeepScan-Fixture-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($deepFixtureRoot)
        $cleanRoot = Join-Path $deepFixtureRoot 'CleanApp'
        $suspiciousRoot = Join-Path $deepFixtureRoot 'SuspiciousApp'
        $tamperedRoot = Join-Path $deepFixtureRoot 'TamperedApp'
        foreach ($path in @($cleanRoot,$suspiciousRoot,$tamperedRoot)) { [void][IO.Directory]::CreateDirectory($path) }
        $cleanExe = Join-Path $cleanRoot 'CleanApp.exe'
        $cleanDocumentation = Join-Path $cleanRoot 'KMSAuto-removal-notes.txt'
        $suspiciousExe = Join-Path $suspiciousRoot 'SuspiciousApp.exe'
        $suspiciousArtifact = Join-Path $suspiciousRoot 'license-crack.ps1'
        $tamperedExe = Join-Path $tamperedRoot 'TamperedApp.exe'
        [IO.File]::WriteAllText($cleanExe, 'clean-fixture', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($cleanDocumentation, 'documentation fixture only', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($suspiciousExe, 'suspicious-fixture-main', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($suspiciousArtifact, 'fixture only', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($tamperedExe, 'known-bad-fixture', (New-Object Text.UTF8Encoding($false)))
        $knownBadHash = Get-ToolSoftwareFileSha256 -Path $tamperedExe
        if ($knownBadHash -notmatch '^[0-9A-F]{64}$') { throw 'Không tạo được SHA-256 fixture.' }
        $deepCatalog = [pscustomobject]@{
            CatalogSource='Fixture'; CatalogVersion='1.1.0.0'; DeepScan=[pscustomobject]@{ KnownActivatorNamePatterns=@(); SuspiciousArtifactNamePatterns=@(); KnownBadSha256=@() }
            Products=@(
                [pscustomobject]@{
                    Id='tampered-fixture'; Vendor='FixtureVendor'; NamePatterns=@('^Tampered App$'); PublisherPatterns=@('^FixtureVendor$')
                    LicenseModel='Paid'; OfficialUrl='https://example.invalid/'; LicenseDomains=@(); UnauthorizedNamePatterns=@()
                    KnownBadSha256=@($knownBadHash); CriticalFilePatterns=@('TamperedApp\.exe$'); ExpectedSignedFilePatterns=@(); ExpectedSignerPatterns=@()
                },
                [pscustomobject]@{
                    Id='suspicious-fixture'; Vendor='FixtureVendor'; NamePatterns=@('^Suspicious App$'); PublisherPatterns=@('^FixtureVendor$')
                    LicenseModel='Paid'; OfficialUrl='https://example.invalid/'; LicenseDomains=@(); UnauthorizedNamePatterns=@()
                    KnownBadSha256=@(); CriticalFilePatterns=@(); ExpectedSignedFilePatterns=@(); ExpectedSignerPatterns=@()
                }
            )
        }
        $deepApps = @(
            [pscustomobject]@{ Id='clean-app'; Name='Clean App'; Version='1'; Publisher='FixtureVendor'; InstallLocation=$cleanRoot; RepresentativePath=$cleanExe; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false },
            [pscustomobject]@{ Id='suspicious-app'; Name='Suspicious App'; Version='1'; Publisher='FixtureVendor'; InstallLocation=$suspiciousRoot; RepresentativePath=$suspiciousExe; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false },
            [pscustomobject]@{ Id='tampered-app'; Name='Tampered App'; Version='1'; Publisher='FixtureVendor'; InstallLocation=$tamperedRoot; RepresentativePath=$tamperedExe; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false }
        )
        $deepAssessment = @(Get-ToolSoftwareAssessments -Applications $deepApps -Catalog $deepCatalog -DeepScan -DeepScanMaximumDurationSeconds 45 -DeepScanMaximumSignatureChecks 80 -DeepScanMaximumHashChecks 40)
        $cleanResult = @($deepAssessment | Where-Object { $_.Id -eq 'clean-app' })[0]
        $suspiciousResult = @($deepAssessment | Where-Object { $_.Id -eq 'suspicious-app' })[0]
        $tamperedResult = @($deepAssessment | Where-Object { $_.Id -eq 'tampered-app' })[0]
        if ([string]$cleanResult.AssessmentCode -ne 'Unverified' -or [int]$cleanResult.EvidenceCount -ne 0) {
            Fail 'Quét sâu báo nhầm ứng dụng fixture sạch hoặc tài liệu có tên activator.'
        }
        if ([string]$suspiciousResult.AssessmentCode -ne 'Suspicious' -or [int]$suspiciousResult.DecisiveEvidenceCount -ne 0 -or -not [bool]$suspiciousResult.CleanupFinding -or
            @($suspiciousResult.Evidence | Where-Object { $_.Code -eq 'SuspiciousArtifactName' }).Count -ne 1) {
            Fail 'Tên crack tổng quát phải chỉ tạo trạng thái Suspicious, không được tự kết luận NonGenuine.'
        }
        if ([string]$tamperedResult.AssessmentCode -ne 'NonGenuine' -or [int]$tamperedResult.DecisiveEvidenceCount -lt 1 -or
            @($tamperedResult.Evidence | Where-Object { $_.Code -eq 'KnownBadFileHash' -and $_.Strength -eq 'Conclusive' }).Count -ne 1) {
            Fail 'Hash xấu đã biết chưa tạo kết luận NonGenuine có bằng chứng quyết định.'
        }
        $deepMetadata = Get-ToolSoftwareLastDeepScanMetadata
        if (-not [bool]$deepMetadata.Enabled -or [int]$deepMetadata.ApplicationsScanned -ne 3 -or [int]$deepMetadata.RelevantFiles -lt 4) {
            Fail 'Metadata quét sâu không phản ánh đủ fixture ứng dụng/tệp.'
        }

        [IO.File]::Delete($suspiciousArtifact)
        $postCleanupAssessment = @(Get-ToolSoftwareAssessments -Applications @($deepApps[1]) -Catalog $deepCatalog -DeepScan `
            -DeepScanMaximumDurationSeconds 45 -DeepScanMaximumSignatureChecks 20 -DeepScanMaximumHashChecks 20)[0]
        if (-not [bool]$postCleanupAssessment.NeedsReview -or [bool]$postCleanupAssessment.CleanupFinding -or
            [int]$postCleanupAssessment.RemediationEvidenceCount -ne 0 -or
            @($postCleanupAssessment.Evidence | Where-Object { $_.Code -eq 'SuspiciousArtifactName' }).Count -ne 0) {
            Fail 'Sau khi cách ly artifact, bằng chứng kiểm kê chung vẫn đưa ứng dụng quay lại hàng đợi làm sạch.'
        }

        $untrustedCatalog = [pscustomobject]@{
            CatalogSource='OnlineCache'; CatalogVersion='99.0.0.0'; CatalogSha256=('A' * 64)
            DeepScan=[pscustomobject]@{ KnownActivatorNamePatterns=@(); SuspiciousArtifactNamePatterns=@(); KnownBadSha256=@() }
            Products=$deepCatalog.Products
        }
        $untrustedAssessment = @(Get-ToolSoftwareAssessments -Applications @($deepApps[2]) -Catalog $untrustedCatalog -DeepScan `
            -DeepScanMaximumDurationSeconds 45 -DeepScanMaximumSignatureChecks 20 -DeepScanMaximumHashChecks 20)[0]
        if ([string]$untrustedAssessment.AssessmentCode -eq 'NonGenuine' -or [int]$untrustedAssessment.DecisiveEvidenceCount -ne 0 -or
            @($untrustedAssessment.Evidence | Where-Object { $_.Code -eq 'KnownBadFileHash' -and $_.Strength -eq 'Strong' }).Count -ne 1) {
            Fail 'Catalog online không đồng nhất bản tích hợp vẫn tạo kết luận/hash quyết định.'
        }

        $dependencyRoot = Join-Path $deepFixtureRoot 'GenericDependencyApp'
        [void][IO.Directory]::CreateDirectory($dependencyRoot)
        $dependencyExe = Join-Path $dependencyRoot 'GenericDependencyApp.exe'
        $dependencyDll = Join-Path $dependencyRoot 'Qt5Core.dll'
        [IO.File]::WriteAllText($dependencyExe, 'generic-dependency-main', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($dependencyDll, 'generic-dependency-hash-mismatch', (New-Object Text.UTF8Encoding($false)))
        $dependencyFile = Get-Item -LiteralPath $dependencyDll -Force
        $dependencyCacheKey = (([IO.Path]::GetFullPath([string]$dependencyFile.FullName)).ToLowerInvariant() + '|' +
            [string]$dependencyFile.Length + '|' + [string]$dependencyFile.LastWriteTimeUtc.Ticks)
        $script:ToolSoftwareSignatureCache[$dependencyCacheKey] = [pscustomobject][ordered]@{
            Status='HashMismatch'; Publisher='Fixture Publisher'; FileVersion='1'; ProductName='Qt'; CompanyName='Fixture'; Path=$dependencyDll
        }
        $dependencyApp = [pscustomobject]@{
            Id='generic-dependency-app'; Name='Generic Dependency App'; Version='1'; Publisher='FixtureVendor'
            InstallLocation=$dependencyRoot; RepresentativePath=$dependencyExe; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false
        }
        $dependencyAssessment = @(Get-ToolSoftwareAssessments -Applications @($dependencyApp) -Catalog $deepCatalog -DeepScan `
            -DeepScanMaximumDurationSeconds 45 -DeepScanMaximumSignatureChecks 20 -DeepScanMaximumHashChecks 20)[0]
        if ([string]$dependencyAssessment.AssessmentCode -ne 'IntegrityCompromised' -or [int]$dependencyAssessment.DecisiveEvidenceCount -ne 0 -or
            @($dependencyAssessment.Evidence | Where-Object { $_.Code -eq 'DeepSignatureHashMismatch' -and $_.Strength -eq 'Strong' -and -not [bool]$_.Decisive }).Count -ne 1) {
            Fail 'HashMismatch của DLL phụ thuộc chung vẫn bị dùng để tự kết luận NonGenuine.'
        }

        $fairApps = New-Object System.Collections.Generic.List[object]
        foreach ($index in 1..8) {
            $fairRoot = Join-Path $deepFixtureRoot ('FairApp' + $index)
            [void][IO.Directory]::CreateDirectory($fairRoot)
            $fairExe = Join-Path $fairRoot ('FairApp' + $index + '.exe')
            [IO.File]::WriteAllText($fairExe, ('fair-fixture-' + $index), (New-Object Text.UTF8Encoding($false)))
            $fairApps.Add([pscustomobject]@{ Id=('fair-app-' + $index); Name=('Fair App ' + $index); Version='1'; Publisher='FixtureVendor'; InstallLocation=$fairRoot; RepresentativePath=$fairExe; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false })
        }
        $fairAssessment = @(Get-ToolSoftwareAssessments -Applications $fairApps.ToArray() -Catalog $deepCatalog -DeepScan `
            -DeepScanMaximumDurationSeconds 45 -DeepScanMaximumSignatureChecks 20 -DeepScanMaximumHashChecks 20)
        if ($fairAssessment.Count -ne 8 -or @($fairAssessment | Where-Object { [int]$_.DeepScanSignatureChecks -lt 1 }).Count -ne 0) {
            Fail 'Ngân sách chữ ký quét sâu chưa được phân phối cho mọi ứng dụng fixture.'
        }
    } catch {
        Fail "Không chạy được fixture quét sâu phần mềm tổng quát: $($_.Exception.Message)"
    } finally {
        if ($deepFixtureRoot -and (Test-Path -LiteralPath $deepFixtureRoot -PathType Container) -and
            ([IO.Path]::GetFileName($deepFixtureRoot) -match '^Tool-Software-DeepScan-Fixture-[0-9a-f]{32}$')) {
            Remove-Item -LiteralPath $deepFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    try {
        $catalog = Get-Content -LiteralPath (Join-Path $root 'software-license-catalog-v1.0.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $catalogIds = @($catalog.Products | ForEach-Object { [string]$_.Id })
        if ([string]$catalog.CatalogVersion -ne '1.3.1.0' -or $catalogIds.Count -lt 76 -or @($catalogIds | Select-Object -Unique).Count -ne $catalogIds.Count) {
            Fail 'Catalogue phần mềm v4.8 chưa đạt 1.3.1.0 / 76 quy tắc duy nhất.'
        }
        foreach ($requiredCatalogId in @('iobit-driver-booster','winrar','adobe-creative-cloud-paid','autodesk-commercial','commercial-pdf-editors','internet-download-manager','mathworks-matlab-simulink','wiris-mathtype')) {
            if ($catalogIds -notcontains $requiredCatalogId) { Fail "Catalogue phần mềm thiếu quy tắc: $requiredCatalogId" }
        }

        $classificationApps = @(
            (New-ToolSoftwareInventoryRecord -Name 'IObit Driver Booster 13 Pro' -Version '13.0' -Publisher 'IObit' -InstallLocation 'C:\Fixture\DriverBooster' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'MathType 7' -Version '7.8' -Publisher 'WIRIS' -InstallLocation 'C:\Fixture\MathType' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'Wondershare PDFelement' -Version '11.0' -Publisher 'Wondershare' -InstallLocation 'C:\Fixture\PDFelement' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'IDM 6.42' -Version '6.42' -Publisher 'Tonec' -InstallLocation 'C:\Fixture\IDM' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery)
        )
        $classificationResults = @(Get-ToolSoftwareAssessments -Applications $classificationApps -Catalog $catalog)
        $iobitResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'iobit-driver-booster' })
        $mathTypeResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'wiris-mathtype' })
        $pdfResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'commercial-pdf-editors' })
        $idmResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'internet-download-manager' })
        if ($iobitResult.Count -ne 1 -or [string]$iobitResult[0].LicenseModel -ne 'Freemium' -or [bool]$iobitResult[0].IsSystemComponent) {
            Fail 'IObit Driver Booster vẫn bị bỏ sót hoặc phân loại nhầm thành driver hệ thống.'
        }
        if ($mathTypeResult.Count -ne 1 -or [string]$mathTypeResult[0].LicenseModel -ne 'Subscription') {
            Fail 'MathType chưa được nhận diện đúng bằng catalogue.'
        }
        if ($pdfResult.Count -ne 1 -or [string]$pdfResult[0].LicenseModel -ne 'Commercial') { Fail 'PDF editor thương mại chưa được nhận diện đúng bằng catalogue.' }
        if ($idmResult.Count -ne 1 -or [string]$idmResult[0].LicenseModel -ne 'Trialware') { Fail 'Tên ngắn IDM chưa được nhận diện đúng bằng catalogue.' }

        $activationFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-WinRAR-State-Fixture-' + [guid]::NewGuid().ToString('N'))
        $previousAppData = [string]$env:APPDATA
        $previousProgramData = [string]$env:ProgramData
        try {
            $winRarInstallRoot = Join-Path $activationFixtureRoot 'WinRAR'
            $env:APPDATA = Join-Path $activationFixtureRoot 'AppData'
            $env:ProgramData = Join-Path $activationFixtureRoot 'ProgramData'
            foreach ($directory in @($winRarInstallRoot,$env:APPDATA,$env:ProgramData)) { [void][IO.Directory]::CreateDirectory($directory) }
            $winRarProduct = @($catalog.Products | Where-Object { [string]$_.Id -eq 'winrar' })[0]
            $winRarApp = New-ToolSoftwareInventoryRecord -Name 'WinRAR 7.11' -Version '7.11' -Publisher 'win.rar GmbH' -InstallLocation $winRarInstallRoot -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
            if ([string](Get-ToolSoftwareKnownActivationState -Application $winRarApp -CatalogProduct $winRarProduct) -ne 'Unactivated') {
                Fail 'WinRAR không có rarreg.key chưa được xác nhận là chưa kích hoạt.'
            }
            $rarRegPath = Join-Path $winRarInstallRoot 'rarreg.key'
            [IO.File]::WriteAllText($rarRegPath, 'fixture-license', (New-Object Text.UTF8Encoding($false)))
            if ([string](Get-ToolSoftwareKnownActivationState -Application $winRarApp -CatalogProduct $winRarProduct) -ne 'LocalLicensePresent') {
                Fail 'WinRAR có rarreg.key nhưng đầu dò không nhận ra trạng thái giấy phép cục bộ.'
            }
            $registeredWinRarAssessment = @(Get-ToolSoftwareAssessments -Applications @($winRarApp) -Catalog $catalog)[0]
            if (-not [bool]$registeredWinRarAssessment.ManualEligible -or [bool]$registeredWinRarAssessment.AutoEligible -or
                [string]$registeredWinRarAssessment.RemediationAdapter -ne 'WinRAR' -or [string]$registeredWinRarAssessment.RemediationImpact -ne 'LocalLicenseFileReset') {
                Fail 'WinRAR có rarreg.key chưa mở đúng lựa chọn đặt lại thủ công hoặc đang bị chọn tự động không an toàn.'
            }
            [IO.File]::Delete($rarRegPath)
            $winRarAssessment = @(Get-ToolSoftwareAssessments -Applications @($winRarApp) -Catalog $catalog)[0]
            if ([string]$winRarAssessment.AssessmentCode -ne 'Unactivated' -or [string]$winRarAssessment.ActivationStateProbe -ne 'Unactivated' -or [bool]$winRarAssessment.ManualEligible) {
                Fail 'Quét lại WinRAR sau khi bỏ giấy phép cục bộ không giữ trạng thái chưa kích hoạt.'
            }
        } finally {
            $env:APPDATA = $previousAppData
            $env:ProgramData = $previousProgramData
            if ($activationFixtureRoot -and (Test-Path -LiteralPath $activationFixtureRoot -PathType Container)) {
                Remove-Item -LiteralPath $activationFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }

        $recordA = New-ToolSoftwareInventoryRecord -Name 'Example Professional x64' -Version '2.0' -Publisher 'Example Corp' -InstallLocation 'C:\Program Files\Example' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $recordB = New-ToolSoftwareInventoryRecord -Name 'Example Professional' -Version '2.0' -Publisher 'Example Corp' -InstallLocation 'C:\Program Files\Example' -SourceKind 'Shortcut' -SourceDetail 'Start Menu' -SkipSignature -SkipExecutableDiscovery
        $mergedFixture = @(Merge-ToolSoftwareInventoryRecords -Records @($recordA,$recordB))
        if ($mergedFixture.Count -ne 1 -or [int]$mergedFixture[0].MergedRecordCount -ne 2 -or @($mergedFixture[0].DiscoverySources).Count -lt 2) {
            Fail 'Kiểm kê chưa gộp hai nguồn phát hiện của cùng một phần mềm.'
        }
        $abbyyRecordA = New-ToolSoftwareInventoryRecord -Name 'ABBYY FineReader' -Version '16.0.14.7295' -Publisher 'ABBYY Development, Inc.' -InstallLocation 'C:\Program Files\ABBYY FineReader 16' -SourceKind 'Shortcut' -SourceDetail 'Start Menu' -SkipSignature -SkipExecutableDiscovery
        $abbyyRecordB = New-ToolSoftwareInventoryRecord -Name 'ABBYY FineReader PDF by sandyd' -Version '16.0.14.7295' -Publisher 'ABBYY Development, Inc.' -InstallLocation 'C:\Program Files\ABBYY FineReader 16\' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $abbyyMergedFixture = @(Merge-ToolSoftwareInventoryRecords -Records @($abbyyRecordA,$abbyyRecordB))
        if ($abbyyMergedFixture.Count -ne 1 -or [int]$abbyyMergedFixture[0].MergedRecordCount -ne 2 -or [string]$abbyyMergedFixture[0].Name -notmatch 'by sandyd') {
            Fail 'Hai nguồn ABBYY cùng version/publisher/thư mục chưa được gộp hoặc làm mất dấu vết nhận diện.'
        }
        $adobeRecordA = New-ToolSoftwareInventoryRecord -Name 'Adobe Photoshop 2025' -Version '26.0' -Publisher 'Adobe Inc.' -InstallLocation 'C:\Program Files\Adobe\Photoshop 2025' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $adobeRecordB = New-ToolSoftwareInventoryRecord -Name 'Adobe Photoshop 2025' -Version '26.0.0' -Publisher 'Adobe' -InstallLocation 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Adobe' -SourceKind 'Shortcut' -SourceDetail 'Start Menu' -SkipSignature -SkipExecutableDiscovery
        $adobeMergedFixture = @(Merge-ToolSoftwareInventoryRecords -Records @($adobeRecordA,$adobeRecordB))
        if ($adobeMergedFixture.Count -ne 1 -or [int]$adobeMergedFixture[0].MergedRecordCount -ne 2 -or @($adobeMergedFixture[0].InstallLocations).Count -ne 2) {
            Fail 'Registry/Shortcut cùng sản phẩm với version rút gọn và hậu tố hãng chưa được gộp an toàn.'
        }
        $officeRecordA = New-ToolSoftwareInventoryRecord -Name 'Microsoft Office' -Version '16.0.20228.20110' -Publisher 'Microsoft Corporation' -InstallLocation 'C:\Program Files\Microsoft Office 15\ClientX64' -SourceKind 'PortableDiscovery' -SourceDetail 'Executable' -SkipSignature -SkipExecutableDiscovery
        $officeRecordB = New-ToolSoftwareInventoryRecord -Name 'Microsoft Office' -Version '16.0.20228.20158' -Publisher 'Microsoft Corporation' -InstallLocation 'C:\Program Files\Microsoft Office\root\Office16' -SourceKind 'Shortcut' -SourceDetail 'Start Menu' -SkipSignature -SkipExecutableDiscovery
        $officeMergedFixture = @(Merge-ToolSoftwareInventoryRecords -Records @($officeRecordA,$officeRecordB))
        if ($officeMergedFixture.Count -ne 1 -or [int]$officeMergedFixture[0].MergedRecordCount -ne 2 -or @($officeMergedFixture[0].InstallLocations).Count -ne 2) {
            Fail 'Cùng sản phẩm/hãng/dòng phiên bản nhưng khác nguồn và thư mục chưa được gộp kèm đủ vị trí.'
        }
        $halRecordA = New-ToolSoftwareInventoryRecord -Name 'ASUS Ambient HAL' -Version '7.4.0.0' -Publisher 'ASUSTeK COMPUTER INC.' -InstallLocation 'C:\Program Files\ASUS\HAL64' -Architecture '64-bit' -SourceKind 'Registry' -SourceDetail 'HKLM64' -SkipSignature -SkipExecutableDiscovery
        $halRecordB = New-ToolSoftwareInventoryRecord -Name 'ASUS Ambient HAL' -Version '7.4.0.0' -Publisher 'ASUSTeK COMPUTER INC.' -InstallLocation 'C:\Program Files (x86)\ASUS\HAL32' -Architecture '32-bit' -SourceKind 'Registry' -SourceDetail 'HKLM32' -SkipSignature -SkipExecutableDiscovery
        $halMergedFixture = @(Merge-ToolSoftwareInventoryRecords -Records @($halRecordA,$halRecordB))
        if ($halMergedFixture.Count -ne 1 -or @($halMergedFixture[0].Architectures).Count -ne 2 -or -not [bool]$halMergedFixture[0].IsSystemComponent) {
            Fail 'Hai kiến trúc của cùng thành phần hệ thống chưa được gộp kèm dấu vết kiến trúc.'
        }
        $parallelRecord = New-ToolSoftwareInventoryRecord -Name 'Adobe Photoshop 2025' -Version '25.0' -Publisher 'Adobe Inc.' -InstallLocation 'C:\Program Files\Adobe\Photoshop 2024' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        if (@(Merge-ToolSoftwareInventoryRecords -Records @($adobeRecordA,$parallelRecord)).Count -ne 2) {
            Fail 'Hai phiên bản chính khác nhau bị gộp nhầm.'
        }
        if (-not (Test-ToolSoftwareLikelySystemComponent -Name 'Microsoft Visual C++ 2015-2022 Redistributable (x64)' -Publisher 'Microsoft Corporation' -SourceKind 'Registry' -InstallLocation 'C:\Program Files\Microsoft')) {
            Fail 'Bộ lọc chưa nhận diện runtime hệ thống để đưa vào phụ lục chi tiết.'
        }
        if (-not (Test-ToolSoftwareLikelySystemComponent -Name 'Microsoft.WidgetsPlatformRuntime' -Publisher 'CN=Microsoft Corporation, O=Microsoft Corporation' -SourceKind 'Appx' -InstallLocation '')) {
            Fail 'Bộ lọc chưa đưa ứng dụng mặc định/AppX Microsoft vào phụ lục.'
        }
        $integrityCatalog = [pscustomobject]@{ CatalogSource='Fixture'; CatalogVersion='1.3.0.0'; Products=@([pscustomobject]@{
            Id='integrity-fixture'; Vendor='Example'; NamePatterns=@('^Integrity Fixture$'); PublisherPatterns=@('^Example Corp$')
            LicenseModel='Paid'; OfficialUrl='https://example.invalid/'; LicenseDomains=@(); UnauthorizedNamePatterns=@()
        }) }
        $integrityApp = [pscustomobject]@{ Id='integrity-fixture'; Name='Integrity Fixture'; Version='1'; Publisher='Example Corp'; InstallLocation=''; RepresentativePath=''; SourceKind='Registry'; SignatureStatus='HashMismatch'; IsMicrosoft=$false }
        $integrityAssessment = @(Get-ToolSoftwareAssessments -Applications @($integrityApp) -Catalog $integrityCatalog)[0]
        if ([string]$integrityAssessment.AssessmentCode -ne 'IntegrityCompromised' -or [int]$integrityAssessment.DecisiveEvidenceCount -ne 0 -or [bool]$integrityAssessment.ManualEligible) {
            Fail 'HashMismatch đơn lẻ vẫn bị kết luận sai là giấy phép không chính hãng hoặc mở khắc phục bản quyền.'
        }
    } catch {
        Fail "Không chạy được fixture catalogue/gộp trùng/phần mềm hệ thống: $($_.Exception.Message)"
    }
}

if ($softwareCatalogUpdater) {
    foreach ($requiredToken in @('[switch]$ConsentGranted','Update-ToolSoftwareLicenseCatalog','UploadedInventory=$false','SentLicenseKeys=$false')) {
        if ($softwareCatalogUpdater.Text -notmatch [regex]::Escape($requiredToken)) { Fail "Trình cập nhật danh mục thiếu consent/khẳng định riêng tư: $requiredToken" }
    }
    if ($softwareCatalogUpdater.Text -notmatch 'if\s*\(\s*-not\s+\$ConsentGranted\s*\)\s*\{\s*(?:#[^\r\n]*\s*)?exit\s+2\s*\}' -or
        $softwareCatalogUpdater.Text -notmatch 'ConsentGranted\s*=\s*\$ConsentGranted' -or
        $softwareCatalogUpdater.Text -match 'ConsentGranted\s*=\s*\$true') {
        Fail 'Trình cập nhật catalog chưa fail-closed hoặc vẫn ghi đè lựa chọn consent thành true.'
    }
    $nativePowerShell = Join-Path $PSHOME 'powershell.exe'
    if (-not (Test-Path -LiteralPath $nativePowerShell -PathType Leaf)) { $nativePowerShell = (Get-Command powershell.exe -ErrorAction Stop).Source }
    $softwareCatalogUpdaterPath = Join-Path $root 'software-license-online-update.ps1'
    $consentResult = Join-Path ([IO.Path]::GetTempPath()) ('ToolCatalogConsent-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        & $nativePowerShell -NoProfile -ExecutionPolicy RemoteSigned -File $softwareCatalogUpdaterPath -ResultFile $consentResult
        if ($LASTEXITCODE -ne 2 -or (Test-Path -LiteralPath $consentResult)) { Fail 'Không truyền consent không fail-closed với mã 2.' }
        $escapedUpdaterPath = $softwareCatalogUpdaterPath.Replace("'", "''")
        $escapedResultPath = $consentResult.Replace("'", "''")
        $falseConsentCommand = "& '$escapedUpdaterPath' -ResultFile '$escapedResultPath' -ConsentGranted:`$false; exit `$LASTEXITCODE"
        $falseConsentEncoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($falseConsentCommand))
        & $nativePowerShell -NoProfile -ExecutionPolicy RemoteSigned -EncodedCommand $falseConsentEncoded
        if ($LASTEXITCODE -ne 2 -or (Test-Path -LiteralPath $consentResult)) { Fail 'Consent false không fail-closed với mã 2.' }
    } finally {
        if (Test-Path -LiteralPath $consentResult -PathType Leaf) { Remove-Item -LiteralPath $consentResult -Force -ErrorAction SilentlyContinue }
    }
}

if ($backup -and $backup.Text -notmatch 'InstalledSoftwareInventory' -or $backup -and $backup.Text -notmatch 'ThirdPartyInventory') {
    Fail 'Backup chưa ghi danh mục toàn bộ phần mềm bên thứ ba.'
}
if ($restore -and $restore.Text -notmatch 'nonRestorableSkipped' -or $restore -and $restore.Text -notmatch "Properties\['Restorable'\]") {
    Fail 'Restore chưa từ chối tự đưa activator/token cấp phép đã loại bỏ trở lại.'
}
if ($restore -and ($restore.Text -notmatch 'FirewallNotice' -or $restore.Text -notmatch 'LicenseNotice.+FirewallNotice')) {
    Fail 'Restore chưa nhận diện thông báo quy tắc Firewall không thể tự khôi phục.'
}
if ($backup -and ($backup.Text -notmatch 'BackupScope=\$Scope' -or $backup.Text -notmatch 'ActivatorTask.+?Restorable=\$false' -or $backup.Text -notmatch 'ActivatorService' -or $backup.Text -notmatch 'ActivatorHook')) {
    Fail 'Backup theo phạm vi chưa khóa task/service/hook activator khỏi khôi phục.'
}
if ($restore -and ($restore.Text -notmatch 'Get-RestoreItemsForScope' -or $restore.Text -notmatch 'scopeNoItems')) {
    Fail 'Restore chưa lọc manifest theo Windows/Office/phần mềm.'
}
$scanOptimizationPath = Join-Path $root 'Tool-ScanOptimization.ps1'
if (-not (Test-Path -LiteralPath $scanOptimizationPath -PathType Leaf)) {
    Fail 'Thiếu Tool-ScanOptimization.ps1.'
} else {
    $scanOptimizationText = Get-Content -LiteralPath $scanOptimizationPath -Raw -Encoding UTF8
    if ($scanOptimizationText -notmatch 'PerCommandTimeoutSeconds\s*=\s*45' -or $scanOptimizationText -notmatch 'WaitForExit' -or $scanOptimizationText -notmatch 'TimedOut') {
        Fail 'Quét Office chưa có timeout cứng và trạng thái timeout.'
    }
}

$nativePattern = '(?im)(?:&|Start-Process\s+)(?:sc|reg|cscript|certutil|sfc|netsh|w32tm|explorer|notepad)\.exe\b'
foreach ($name in @('Giao-Dien.ps1','kiem-tra-cau-hinh-ban-quyen.ps1','windows-license-backup.ps1','windows-license-compliance-cleanup.ps1','windows-license-restore.ps1','windows-license-deep-scan.ps1','windows-license-forensics.ps1')) {
    $path = Join-Path $root $name
    if ((Test-Path -LiteralPath $path -PathType Leaf) -and (Get-Content -LiteralPath $path -Raw -Encoding UTF8) -match $nativePattern) {
        Fail "Lời gọi native executable còn phụ thuộc PATH: $name"
    }
}

if ($failures.Count) {
    foreach ($failure in $failures) { Write-Error $failure -ErrorAction Continue }
    Write-Host "VERIFY-SAFETY-REGRESSIONS: FAILED ($($failures.Count) errors)"
    exit 1
}
Write-Host 'VERIFY-SAFETY-REGRESSIONS: OK (all-software inventory + consent-only HTTPS catalog + scoped backup/restore + fail-closed remediation + bounded scans)' -ForegroundColor Green
exit 0
