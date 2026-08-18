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
$elevatedBridge = Read-And-Parse 'Tool-ElevatedBridge.ps1'
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
            $officeOfficialDependencyAst = $cleanup.Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ConvertFrom-OfficeOfficialLicenseStatus' }, $true)
            if (-not $officeOfficialDependencyAst) { throw 'Missing ConvertFrom-OfficeOfficialLicenseStatus' }
            Invoke-Expression ('function script:ConvertFrom-OfficeOfficialLicenseStatus ' + $officeOfficialDependencyAst.Body.Extent.Text)
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
    $officeOfficialParserAst = $cleanup.Ast.Find({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ConvertFrom-OfficeOfficialLicenseStatus' }, $true)
    if (-not $officeOfficialParserAst) {
        Fail 'Không tìm thấy parser hậu kiểm bản quyền Office chính thức.'
    } else {
        try {
            $officeOfficialParser = $officeOfficialParserAst.Body.GetScriptBlock()
            $officeOfficialFixture = @'
---------------------------------------
SKU ID: aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa
LICENSE NAME: Office 16, Office16ProPlusR_Retail edition
LICENSE DESCRIPTION: Office 16, RETAIL channel
LICENSE STATUS: ---LICENSED---
Last 5 characters of installed product key: ABCDE
---------------------------------------
SKU ID: bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb
LICENSE NAME: Office 16, Office16ProjectVL_KMS_Client edition
LICENSE DESCRIPTION: Office 16, VOLUME_KMSCLIENT channel
LICENSE STATUS: ---UNLICENSED---
---------------------------------------
'@
            $officialEntries = @(& $officeOfficialParser -StatusText $officeOfficialFixture -Path 'C:\Office\OSPP.VBS')
            if ($officialEntries.Count -ne 2 -or
                @($officialEntries | Where-Object { $_.LicenseStatusCode -eq 'Licensed' -and $_.Channel -eq 'Retail' }).Count -ne 1 -or
                @($officialEntries | Where-Object { $_.LicenseStatusCode -eq 'Unlicensed' -and $_.Channel -eq 'KMS' }).Count -ne 1) {
                Fail 'Parser hậu kiểm Office không tách đúng Licensed Retail và Unlicensed KMS.'
            }
        } catch {
            Fail "Không chạy được parser hậu kiểm Office chính thức: $($_.Exception.Message)"
        }
    }

    if ($cleanup.Text -notmatch '/dstatusall' -or $cleanup.Text -notmatch 'selectedOfficeTargetIds' -or $cleanup.Text -notmatch 'Get-AllCleanupCandidates') {
        Fail 'Cleanup Office chưa quét /dstatusall, chọn theo SKU hoặc tái tạo danh sách tồn dư sau hậu kiểm.'
    }
    foreach ($requiredToken in @('Get-InstalledSoftwareInventory','Get-ThirdPartyStrongEvidence','Get-ThirdPartyLicenseCandidates','Get-ThirdPartyGenericRemediationPlan','Get-ThirdPartyHostsUpdate','Connect-ThirdPartyApplicationsToCandidates','ThirdPartyLicenseReset','ThirdPartyLicenseState','ThirdPartyUninstallEntry','ThirdPartyHostsEntry','ThirdPartyFirewallBlock','FirewallNotice','RemoveScopedFirewallBlock','ThirdPartyMsiRepair','ThirdPartyOfficialSource','LocalLicenseFileReset','FileArtifact','CleanupFinding','ThirdPartyRemediationFindingCount','SystemChangeCount','ThirdPartyExecutionResults','NoAutomaticChange','SelectionAccepted','SelectionContainsUnknownIds','AllowCurrentUserForUserScope','SelectionSchemaInvalid','SelectedThirdPartyResolvedCount','SelectedThirdPartyRemainingCount','PostCheckStatus','RemediationFailed','softwareUninstallBlocked','PolicyBlocked','BlockApplicationUninstall','Test-CleanupKnownActivatorText','Win32_StartupCommand','erturk-dev\.netlify\.app/run','Get-OfficialLicensePostCheck','OfficiallyLicensed','VendorConfirmed','OpenWindowsActivation','OpenOfficeActivation','OpenVendorActivation','OpenVendorRepair','ReviewVendorActivation')) {
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
        $cleanup.Text -notmatch [regex]::Escape("Kind='ThirdPartyHostsEntry'; Restorable=`$true")) {
        Fail 'Fallback tổng quát chưa khóa MSI Repair vào đường dẫn hệ thống/product code hoặc chưa cho phép hoàn tác hosts.'
    }
    if ($cleanup.Text -match [regex]::Escape("-Arguments @('/x', `$productCode") -or
        $cleanup.Text -match 'ThirdPartyMsiUninstall') {
        Fail 'Tool còn nhánh gỡ ứng dụng MSI; chính sách chỉ cho loại bỏ crack/activator đã bị vi phạm.'
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
        foreach ($inventoryFunctionName in @('Get-ToolSoftwareHostsLineMappings','Test-ToolSoftwareRemediationEvidence')) {
            $inventoryFunctionAst = $softwareInventory.Ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $inventoryFunctionName
            }, $true)
            if (-not $inventoryFunctionAst) { throw "Missing function: $inventoryFunctionName" }
            Invoke-Expression ('function script:' + $inventoryFunctionName + ' ' + $inventoryFunctionAst.Body.Extent.Text)
        }
        foreach ($name in @('Get-ToolDataOwnerSid','Set-ProtectedBackupAcl','Test-ProtectedDirectoryAcl','Get-SelectedCleanupIds','Test-CleanupScanScopeIncludes','Get-CleanupRecordComponentScope','Test-CleanupRecordMatchesScope','Get-ScopedCleanupCandidates','Get-ThirdPartyNormalizedInstallRoot','Get-ThirdPartyMsiProductCode','Test-ThirdPartyArtifactPath','Test-ThirdPartyApplicationPathScope','Get-ThirdPartyHostsUpdate','Get-ThirdPartyGenericRemediationPlan','Get-ThirdPartyLicenseStatePaths','Get-ThirdPartyRemediationPlan','Test-ThirdPartyApplicationCleanupEligible','Get-ThirdPartyLicenseCandidates','New-CleanupItem','Expand-SelectedCleanupCandidates','Get-DryRunRemediationPlan','Add-ThirdPartyVerification','Test-CleanupScopeReady','Test-CleanupKnownActivatorText','Get-LicenseChannel','Test-ApprovedKms','Get-WindowsOfficialLicenseOutcome','Get-OfficeOfficialLicenseOutcome','Get-ThirdPartyOfficialLicenseOutcomes','Get-CleanupNextActions')) {
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
        $malformedHostsFixture = Get-ThirdPartyHostsUpdate -Lines @(
            '0.0.0.0 adobe-license.example127.0.0.1 easeus-license.example # joined mappings'
        ) -Targets @('adobe-license.example')
        $malformedHostsText = @($malformedHostsFixture.Lines) -join "`n"
        if ([int]$malformedHostsFixture.RemovedCount -ne 1 -or
            $malformedHostsText -match 'adobe-license\.example' -or
            $malformedHostsText -notmatch '(?im)^127\.0\.0\.1\s+easeus-license\.example' -or
            $malformedHostsText -notmatch '# joined mappings') {
            Fail 'Fixture hosts bị dính hai mapping chưa gỡ đúng domain đích hoặc làm mất mapping/comment còn lại.'
        }

        $selectionFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-Selection-Acl-Fixture-' + [guid]::NewGuid().ToString('N'))
        $previousDataScope = [string]$env:TOOL_DATA_SCOPE
        $previousDataOwnerSid = [string]$env:TOOL_DATA_OWNER_SID
        $previousSecureLaunch = [string]$env:TOOL_SECURE_LAUNCH
        $previousRuntimeDirectory = [string]$env:TOOL_SECURE_RUNTIME_DIR
        try {
            [void][IO.Directory]::CreateDirectory($selectionFixtureRoot)
            $administratorsSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
            $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
            $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
            $fixtureAcl = New-Object Security.AccessControl.DirectorySecurity
            $fixtureAcl.SetAccessRuleProtection($true, $false)
            $fixtureAcl.SetOwner($currentUserSid)
            foreach ($sid in @($administratorsSid,$systemSid,$currentUserSid)) {
                $fixtureAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl',$inheritance,'None','Allow')))
            }
            Set-Acl -LiteralPath $selectionFixtureRoot -AclObject $fixtureAcl -ErrorAction Stop
            $env:TOOL_DATA_SCOPE = 'User'
            $env:TOOL_DATA_OWNER_SID = $currentUserSid.Value
            Set-ProtectedBackupAcl -Path $selectionFixtureRoot -AllowCurrentUserForUserScope
            if (-not (Test-ProtectedDirectoryAcl -Path $selectionFixtureRoot -AllowCurrentUserForUserScope) -or
                (Test-ProtectedDirectoryAcl -Path $selectionFixtureRoot)) {
                Fail 'ACL runtime theo người dùng chưa được cleanup chấp nhận đúng phạm vi hoặc bị chấp nhận khi không bật user-scope.'
            }
            $ownerAcl = Get-Acl -LiteralPath $selectionFixtureRoot -ErrorAction Stop
            $ownerRuleCount = @($ownerAcl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]) | Where-Object {
                $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
                $_.IdentityReference.Value -eq $currentUserSid.Value -and
                ($_.FileSystemRights -band [Security.AccessControl.FileSystemRights]::FullControl) -ne 0
            }).Count
            if ($ownerRuleCount -lt 1) { Fail 'ACL parent user-scope không giữ quyền FullControl cho SID người dùng ban đầu.' }

            $env:TOOL_SECURE_LAUNCH = '1'
            $env:TOOL_SECURE_RUNTIME_DIR = $selectionFixtureRoot
            $script:SelectionFile = Join-Path $selectionFixtureRoot 'selection.json'
            $script:ScanScope = 'ThirdParty'
            [pscustomobject][ordered]@{
                SchemaVersion='1.0'; RequestId=[guid]::NewGuid().ToString('D')
                CreatedAtUtc=[DateTimeOffset]::UtcNow.ToString('o'); SelectedIds=@('application|fixture'); ScanScope='ThirdParty'
            } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SelectionFile -Encoding UTF8
            function script:Test-ProtectedDirectoryAcl { param([string]$Path,[switch]$AllowCurrentUserForUserScope); return $true }
            $acceptedIds = @(Get-SelectedCleanupIds)
            if (-not [bool]$script:SelectionAccepted -or $acceptedIds.Count -ne 1 -or $acceptedIds[0] -ne 'application|fixture') {
                Fail 'SelectionFile hợp lệ vẫn bị tiến trình cleanup quyền quản trị làm rỗng.'
            }
            $tamperedSelection = Get-Content -LiteralPath $script:SelectionFile -Raw | ConvertFrom-Json
            $tamperedSelection.ScanScope = 'All'
            $tamperedSelection | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SelectionFile -Encoding UTF8
            if (@(Get-SelectedCleanupIds).Count -ne 0 -or [bool]$script:SelectionAccepted -or [string]$script:SelectionErrorCode -ne 'SelectionScopeMismatch') {
                Fail 'SelectionFile sai phạm vi không bị từ chối fail-closed.'
            }
            Import-CleanupFunctionForFixture 'Test-ProtectedDirectoryAcl'
        } finally {
            $env:TOOL_DATA_SCOPE = $previousDataScope
            $env:TOOL_DATA_OWNER_SID = $previousDataOwnerSid
            $env:TOOL_SECURE_LAUNCH = $previousSecureLaunch
            $env:TOOL_SECURE_RUNTIME_DIR = $previousRuntimeDirectory
            if ($selectionFixtureRoot -and (Test-Path -LiteralPath $selectionFixtureRoot -PathType Container)) {
                Remove-Item -LiteralPath $selectionFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
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
            $lowConfidenceApp = [pscustomobject]@{
                Id='low-confidence'; Name='Low confidence fixture'; SourceKind='Registry'; Publisher='Example'; VendorScope='Example'
                InstallLocation=$artifactInstallRoot; RepresentativePath=''; RegistryPath=''; UninstallString=''
                Confidence='Low'; CleanupFinding=$true; ManualEligible=$true; AutoEligible=$true; RemediationAdapter='Generic'
                OfficialReferenceUrl='https://example.invalid/'
                Evidence=@([pscustomobject]@{ Code='KnownActivatorArtifact'; Source='Fixture'; Detail=$artifactPath; Strength='Strong'; Decisive=$true })
            }
            if (@(Get-ThirdPartyLicenseCandidates -Applications @($lowConfidenceApp) -Evidence @()).Count -ne 0) {
                Fail 'Ứng dụng Low confidence vẫn lọt vào danh sách khắc phục dù cờ đầu vào bị đặt sai.'
            }
            $unlinkedEvidenceApp = [pscustomobject]@{
                Id='unlinked-evidence'; Name='Unlinked evidence fixture'; SourceKind='Registry'; Publisher='Example'; VendorScope='Example'
                InstallLocation=$artifactInstallRoot; RepresentativePath=''; RegistryPath=''; UninstallString=''
                Confidence='Medium'; CleanupFinding=$true; ManualEligible=$true; AutoEligible=$true; RemediationAdapter='Generic'
                OfficialReferenceUrl='https://example.invalid/'
                Evidence=@([pscustomobject]@{ Code='InventoryObservation'; Source='Fixture'; Detail='No activator/tampering link'; Strength='Strong'; Decisive=$true })
            }
            if (@(Get-ThirdPartyLicenseCandidates -Applications @($unlinkedEvidenceApp) -Evidence @()).Count -ne 0) {
                Fail 'Ứng dụng không có bằng chứng activator/tampering vẫn lọt vào danh sách khắc phục.'
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
        ) -Included
        if ([int]$verificationFixture.ThirdPartyNeedsReviewCount -ne 1 -or
            [int]$verificationFixture.ThirdPartyRemediationFindingCount -ne 0 -or
            -not [bool]$verificationFixture.ReadyForOfficialActivation -or
            -not (Test-CleanupScopeReady -Verification $verificationFixture -Scope ThirdParty)) {
            Fail 'Phần mềm chỉ Chưa xác minh vẫn chặn hậu kiểm hoặc quay lại hàng đợi làm sạch.'
        }
        $standaloneVerificationFixture = [pscustomobject]@{
            ScanWarningCount=0; ThirdPartyCandidateCount=0; ReadyForOfficialActivation=$true
            Conclusion='READY-MARKER'; HandlingGuidance=@(); ReadinessChecks=@(); ScopeNote=''
        }
        $standaloneVerificationFixture = Add-ThirdPartyVerification -Verification $standaloneVerificationFixture `
            -ThirdPartyCandidates @($standaloneCandidates) -ThirdPartyApplications @() -Included
        if ([int]$standaloneVerificationFixture.ThirdPartyRemediationFindingCount -ne 1 -or
            [bool]$standaloneVerificationFixture.ReadyForOfficialActivation -or
            [string]$standaloneVerificationFixture.Conclusion -match 'READY-MARKER' -or
            (Test-CleanupScopeReady -Verification $standaloneVerificationFixture -Scope ThirdParty)) {
            Fail 'Candidate tệp activator độc lập không chặn hậu kiểm hoặc vẫn giữ kết luận ĐẠT mâu thuẫn trước khi được cách ly.'
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
        if (@($candidates[0].PlanItems | Where-Object { $_.Type -eq 'Uninstall' }).Count -ne 0 -or
            @($candidates[0].PlanItems | Where-Object { $_.Type -eq 'Repair' }).Count -ne 0 -or
            @($candidates[0].PlanItems | Where-Object { $_.Type -eq 'Guidance' }).Count -ne 1) {
            Fail 'Fixture ABBYY đóng gói trái phép còn kế hoạch gỡ/Repair ứng dụng thay vì chỉ hướng dẫn cài lại thủ công.'
        }

        $repairGuid = '{11111111-2222-3333-4444-555555555555}'
        $repairApp = [pscustomobject]@{ Id='example-pro'; Name='Example Pro'; SourceKind='Registry'; Publisher='Example'; VendorScope='Example'; InstallLocation='C:\Program Files\Example Pro'; RepresentativePath='C:\Program Files\Example Pro\Example.exe'; RegistryPath=('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + $repairGuid); UninstallString=('MsiExec.exe /I' + $repairGuid); ManualEligible=$true; AutoEligible=$true; RemediationAdapter='Generic'; OfficialReferenceUrl='https://example.invalid/'; Evidence=@([pscustomobject]@{ Code='SignatureHashMismatch'; Source='Authenticode'; Detail='C:\Program Files\Example Pro\Example.exe'; Strength='Strong' }) }
        $repairCandidate = @(Get-ThirdPartyLicenseCandidates -Applications @($repairApp) -Evidence @())
        if ($repairCandidate.Count -ne 1 -or -not [bool]$repairCandidate[0].AutoEligible -or [string]$repairCandidate[0].RemediationMode -ne 'AutomaticOfficialRepair' -or @($repairCandidate[0].PlanItems | Where-Object { $_.Type -eq 'Repair' -and $_.Location -eq $repairGuid }).Count -ne 1) {
            Fail 'Fixture MSI bị sửa chưa tạo đúng kế hoạch Repair tự động an toàn.'
        }

        $adobeRiskEvidence = [pscustomobject]@{ Code='KnownActivatorArtifact'; Source='Fixture'; Detail='Adobe GenP'; Strength='Strong'; Decisive=$true }
        $adobeFamily = @(
            [pscustomobject]@{ Id='adobe-risk'; Name='Adobe Photoshop'; Publisher='Adobe'; VendorScope='Adobe'; InstallLocation='C:\Program Files\Adobe\Photoshop'; RepresentativePath=''; SourceKind='Registry'; RegistryPath=''; UninstallString=''; AssessmentCode='NonGenuine'; LicenseTechnicalState='CrackConfirmed'; CleanupFinding=$true; ManualEligible=$true; AutoEligible=$true; StrongEvidenceCount=1; RemediationAdapter='Adobe'; OfficialReferenceUrl='https://account.adobe.com/'; Evidence=@($adobeRiskEvidence) },
            [pscustomobject]@{ Id='adobe-valid'; Name='Adobe Acrobat'; Publisher='Adobe'; VendorScope='Adobe'; InstallLocation='C:\Program Files\Adobe\Acrobat'; RepresentativePath=''; SourceKind='Registry'; RegistryPath=''; UninstallString=''; AssessmentCode='GenuineVerified'; LicenseTechnicalState='LocalLicenseVerified'; CleanupFinding=$false; ManualEligible=$false; AutoEligible=$false; StrongEvidenceCount=0; RemediationAdapter='Adobe'; OfficialReferenceUrl='https://account.adobe.com/'; Evidence=@() }
        )
        $adobeExternalEvidence = [pscustomobject]@{
            Type='InstalledActivator'; VendorScope='Adobe'; Name='Adobe GenP'; RegistryPath='HKEY_LOCAL_MACHINE\SOFTWARE\Fixture\AdobeGenP'
            Location=''; Detail='fixture'; Strength='Strong'; Decisive=$true
        }
        $adobePreserveCandidate = @(Get-ThirdPartyLicenseCandidates -Applications $adobeFamily -Evidence @($adobeExternalEvidence))
        if ($adobePreserveCandidate.Count -ne 1 -or [string]$adobePreserveCandidate[0].RemediationMode -ne 'ArtifactCleanupPreserveVerifiedLicense' -or
            @($adobePreserveCandidate[0].PlanItems | Where-Object { [string]$_.Kind -eq 'ThirdPartyLicenseState' }).Count -ne 0) {
            Fail 'Adapter Adobe chưa bảo toàn shared license đã được vendor xác nhận.'
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
        $blockedUninstallCandidate = New-CleanupItem -Type 'Uninstall' -Kind 'FixtureApplicationUninstall' -Name 'Fixture App' -Location '{AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE}' -Detail 'fixture'
        $blockedUninstallPlan = @(Get-DryRunRemediationPlan -Candidates @($blockedUninstallCandidate) -SelectedIds @([string]$blockedUninstallCandidate.Id))
        $blockedAction = @($blockedUninstallPlan | Where-Object { $_.ActionCode -eq 'BlockApplicationUninstall' })
        if ($blockedAction.Count -ne 1 -or [bool]$blockedAction[0].ChangesSystem) {
            Fail 'Dry Run không chặn fail-closed kế hoạch gỡ ứng dụng.'
        }
        $dryRunFirewallCandidate = New-CleanupItem -Type 'Firewall' -Kind 'ThirdPartyFirewallBlock' -Name 'Fixture outbound block' -Location 'C:\Fixture\Example.exe' -Detail 'fixture'
        $dryRunFirewallPlan = @(Get-DryRunRemediationPlan -Candidates @($dryRunFirewallCandidate) -SelectedIds @([string]$dryRunFirewallCandidate.Id))
        if ($dryRunFirewallPlan.Count -ne 3 -or
            @($dryRunFirewallPlan | Where-Object { $_.ActionCode -eq 'RemoveScopedFirewallBlock' -and -not [bool]$_.Restorable }).Count -ne 1) {
            Fail 'Dry Run chưa công bố đúng hành động Firewall manual-only, không tự khôi phục.'
        }

        $scopeCandidates = @(
            (New-CleanupItem -Type 'Registry' -Kind 'SppNoGenTicketPolicy' -Name 'win' -Location 'HKLM:\Fixture\Windows' -Detail 'fixture' -ComponentScope 'Windows'),
            (New-CleanupItem -Type 'License' -Kind 'OfficeKmsLicense' -Name 'office' -Location 'C:\Fixture\OSPP.VBS' -Detail 'fixture' -ComponentScope 'Office'),
            (New-CleanupItem -Type 'File' -Kind 'ThirdPartyUnauthorizedArtifact' -Name 'software' -Location 'C:\Fixture\Software\patch.dll' -Detail 'fixture' -ComponentScope 'ThirdParty'),
            (New-CleanupItem -Type 'Service' -Kind 'ActivatorService' -Name 'shared' -Location 'C:\Fixture\activator.exe' -Detail 'fixture' -ComponentScope 'Shared')
        )
        $scopeExpectations = [ordered]@{
            Windows=@('shared','win')
            Office=@('office','shared')
            ThirdParty=@('software')
            WindowsOffice=@('office','shared','win')
            WindowsThirdParty=@('shared','software','win')
            OfficeThirdParty=@('office','shared','software')
            All=@('office','shared','software','win')
        }
        foreach ($scopeName in $scopeExpectations.Keys) {
            $scoped = @(Get-ScopedCleanupCandidates -CleanupItems $scopeCandidates -Scope $scopeName)
            $actualNames = @($scoped | ForEach-Object { [string]$_.Name } | Sort-Object)
            $expectedNames = @($scopeExpectations[$scopeName] | Sort-Object)
            if (($actualNames -join '|') -ne ($expectedNames -join '|')) {
                Fail "Phạm vi $scopeName lọc sai: thực tế=$($actualNames -join ','), mong đợi=$($expectedNames -join ',')."
            }
            $scopePlan = @(Get-DryRunRemediationPlan -Candidates $scoped -SelectedIds @($scoped | ForEach-Object { [string]$_.Id }) -SkipRestorePoint)
            $plannedCandidateIds = @($scopePlan | Where-Object { [string]$_.CandidateId -notin @('signed-backup-bundle','system-restore-point') } | ForEach-Object { [string]$_.CandidateId } | Sort-Object -Unique)
            $expectedCandidateIds = @($scoped | ForEach-Object { [string]$_.Id } | Sort-Object -Unique)
            if (($plannedCandidateIds -join '|') -ne ($expectedCandidateIds -join '|')) {
                Fail "Dry Run phạm vi $scopeName không lập đúng hành động cho từng mục đã lọc."
            }
        }

        $readyBase = [pscustomobject]@{
            ScanWarningCount=0; ActiveActivatorFindingCount=0; ConfigurationResidueCount=0
            UnapprovedWindowsKmsCount=0; UnapprovedOfficeKmsCount=0; ThirdPartyRemediationFindingCount=0
        }
        if (-not (Test-CleanupScopeReady -Verification $readyBase -Scope 'All')) { Fail 'Trạng thái sạch của cả ba phạm vi bị báo sai.' }
        $windowsBlocked = $readyBase.PSObject.Copy(); $windowsBlocked.UnapprovedWindowsKmsCount = 1
        if (Test-CleanupScopeReady -Verification $windowsBlocked -Scope 'Windows') { Fail 'Windows KMS còn tồn tại nhưng phạm vi Windows vẫn báo sẵn sàng.' }
        if (-not (Test-CleanupScopeReady -Verification $windowsBlocked -Scope 'Office')) { Fail 'Lỗi chỉ thuộc Windows đã chặn nhầm phạm vi Office.' }
        $officeBlocked = $readyBase.PSObject.Copy(); $officeBlocked.UnapprovedOfficeKmsCount = 1
        if (Test-CleanupScopeReady -Verification $officeBlocked -Scope 'Office') { Fail 'Office KMS còn tồn tại nhưng phạm vi Office vẫn báo sẵn sàng.' }
        if (-not (Test-CleanupScopeReady -Verification $officeBlocked -Scope 'Windows')) { Fail 'Lỗi chỉ thuộc Office đã chặn nhầm phạm vi Windows.' }
        $softwareBlocked = $readyBase.PSObject.Copy(); $softwareBlocked.ThirdPartyRemediationFindingCount = 1
        if (Test-CleanupScopeReady -Verification $softwareBlocked -Scope 'ThirdParty') { Fail 'Phần mềm còn phát hiện cần xử lý nhưng phạm vi phần mềm vẫn báo sẵn sàng.' }
        if (-not (Test-CleanupScopeReady -Verification $softwareBlocked -Scope 'WindowsOffice')) { Fail 'Lỗi chỉ thuộc phần mềm đã chặn nhầm Windows/Office.' }

        function script:Get-Oa3KeyPresent { return $false }
        $script:ApprovedKmsServers = @('kms.corp.example')
        $officialVerification = [pscustomobject]@{
            ScanWarningCount=0; ActiveActivatorFindingCount=0; ConfigurationResidueCount=0
            UnapprovedWindowsKmsCount=0; UnapprovedOfficeKmsCount=0; ThirdPartyRemediationFindingCount=0
            ReadinessChecks=@()
        }
        $retailWindows = [pscustomobject]@{
            LicenseStatus=1; Description='Windows(R) Operating System, RETAIL channel'
            KeyManagementServiceMachine=''; Name='Windows'; ID='fixture'; PartialProductKey='ABCDE'
        }
        $windowsLicensed = Get-WindowsOfficialLicenseOutcome -Products @($retailWindows) -Verification $officialVerification -Included $true
        if (-not [bool]$windowsLicensed.OfficiallyLicensed -or -not [bool]$windowsLicensed.VendorConfirmed -or
            [string]$windowsLicensed.StateCode -ne 'Licensed') {
            Fail 'Windows Retail chính thức, hậu kiểm sạch chưa trả OfficiallyLicensed=True.'
        }
        $windowsUnactivated = Get-WindowsOfficialLicenseOutcome -Products @(
            [pscustomobject]@{ LicenseStatus=0; Description='Windows(R), RETAIL channel'; KeyManagementServiceMachine=''; Name='Windows' }
        ) -Verification $officialVerification -Included $true
        if ([bool]$windowsUnactivated.OfficiallyLicensed -or [string]$windowsUnactivated.StateCode -ne 'Unactivated' -or
            [string]$windowsUnactivated.OfficialActionCode -ne 'OpenWindowsActivation') {
            Fail 'Windows chưa kích hoạt không giữ False hoặc thiếu hành động mở Activation chính thức.'
        }
        $windowsDirtyVerification = $officialVerification.PSObject.Copy(); $windowsDirtyVerification.ActiveActivatorFindingCount = 1
        $windowsDirty = Get-WindowsOfficialLicenseOutcome -Products @($retailWindows) -Verification $windowsDirtyVerification -Included $true
        if ([bool]$windowsDirty.OfficiallyLicensed -or [string]$windowsDirty.StateCode -ne 'CrackEvidencePresent') {
            Fail 'Windows vendor báo Licensed nhưng còn activator vẫn bị trả True.'
        }

        $officeRetailLicensed = [pscustomobject]@{ LicenseStatusCode='Licensed'; Channel='Retail'; Server=''; LicenseName='Office Retail' }
        $officeLicensed = Get-OfficeOfficialLicenseOutcome -LicenseEntries @($officeRetailLicensed) -Verification $officialVerification -Included $true -Installed $true
        if (-not [bool]$officeLicensed.OfficiallyLicensed -or -not [bool]$officeLicensed.VendorConfirmed -or [string]$officeLicensed.StateCode -ne 'Licensed') {
            Fail 'Office Retail do OSPP xác nhận và hậu kiểm sạch chưa trả True.'
        }
        $officeUnactivated = Get-OfficeOfficialLicenseOutcome -LicenseEntries @(
            [pscustomobject]@{ LicenseStatusCode='Unlicensed'; Channel='Retail'; Server=''; LicenseName='Office Retail' }
        ) -Verification $officialVerification -Included $true -Installed $true
        if ([bool]$officeUnactivated.OfficiallyLicensed -or [string]$officeUnactivated.StateCode -ne 'Unactivated' -or
            [string]$officeUnactivated.OfficialActionCode -ne 'OpenOfficeActivation') {
            Fail 'Office Unlicensed không giữ False hoặc thiếu hành động kích hoạt chính thức.'
        }

        $thirdPartyOutcomes = @(Get-ThirdPartyOfficialLicenseOutcomes -Applications @(
            [pscustomobject]@{ Id='licensed'; Name='Licensed App'; Publisher='Vendor'; VendorScope='Vendor'; LicenseModel='Paid'; AssessmentCode='GenuineVerified'; LicenseTechnicalState='LocalLicenseVerified'; CleanupFinding=$false; OfficialReferenceUrl='https://vendor.example/license' },
            [pscustomobject]@{ Id='artifact-only'; Name='Artifact App'; Publisher='Vendor'; VendorScope='Vendor'; LicenseModel='Paid'; AssessmentCode='Unverified'; LicenseTechnicalState='Unverified'; CleanupFinding=$false; OfficialReferenceUrl='https://vendor.example/license' },
            [pscustomobject]@{ Id='repair'; Name='Repair App'; Publisher='Vendor'; VendorScope='Vendor'; LicenseModel='Paid'; AssessmentCode='IntegrityCompromised'; LicenseTechnicalState='Suspicious'; CleanupFinding=$false; OfficialReferenceUrl='https://vendor.example/repair' }
        ) -Included $true)
        if (@($thirdPartyOutcomes | Where-Object { $_.ApplicationId -eq 'licensed' -and [bool]$_.OfficiallyLicensed -and [bool]$_.VendorConfirmed }).Count -ne 1 -or
            @($thirdPartyOutcomes | Where-Object { $_.ApplicationId -eq 'artifact-only' -and [bool]$_.OfficiallyLicensed }).Count -ne 0 -or
            @($thirdPartyOutcomes | Where-Object { $_.ApplicationId -eq 'repair' -and $_.OfficialActionCode -eq 'OpenVendorRepair' }).Count -ne 1) {
            Fail 'Hậu kiểm phần mềm khác đang coi artifact/khởi chạy là bản quyền thật hoặc thiếu NeedsRepair.'
        }

        $nextActionFixture = [pscustomobject]@{
            OfficialActions=@(
                [pscustomobject]@{ Code='OpenOfficeActivation'; Component='Office'; Name='Office'; Target='LocalLicenseManager:Office' },
                [pscustomobject]@{ Code='OpenVendorActivation'; Component='ThirdParty'; Name='Artifact App'; Target='https://vendor.example/license' },
                [pscustomobject]@{ Code='OpenVendorRepair'; Component='ThirdParty'; Name='Same vendor'; Target='https://vendor.example/license' },
                [pscustomobject]@{ Code='OpenVendorActivation'; Component='ThirdParty'; Name='Unsafe URL'; Target='http://vendor.example/license' }
            )
        }
        $nextActions = @(Get-CleanupNextActions -Verification ([pscustomobject]@{
            ScanWarningCount=0; ReadyForOfficialActivation=$true; UnapprovedWindowsKmsCount=0; UnapprovedOfficeKmsCount=0
        }) -CleanupItems @() -ProtectedLicense:$false -OfficialLicensePostCheck $nextActionFixture -Scope 'OfficeThirdParty')
        if (@($nextActions | Where-Object { $_.Code -eq 'OpenLicenseManager' -and @($_.Components) -contains 'Office' }).Count -ne 1 -or
            @($nextActions | Where-Object { $_.Code -eq 'ReviewVendorActivation' -and @($_.Targets).Count -eq 1 -and @($_.Targets | Where-Object { $_.Target -eq 'https://vendor.example/license' }).Count -eq 1 }).Count -ne 1) {
            Fail 'NextActions hậu kiểm chưa phân luồng Office và URL kích hoạt chính thức của phần mềm khác.'
        }
    } catch {
        Fail "Không chạy được fixture khắc phục tổng quát/ABBYY: $($_.Exception.Message) | $($_.ScriptStackTrace)"
    }
}

if ($gui) {
    try {
        $scopeMapperAst = $gui.Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'ConvertTo-CleanupScanScope'
        }, $true)
        if (-not $scopeMapperAst) { throw 'Missing ConvertTo-CleanupScanScope' }
        Invoke-Expression ("function script:ConvertTo-CleanupScanScope " + $scopeMapperAst.Body.Extent.Text)
        $scopeMappingCases = @(
            @($false,$false,$false,''), @($true,$false,$false,'Windows'), @($false,$true,$false,'Office'),
            @($false,$false,$true,'ThirdParty'), @($true,$true,$false,'WindowsOffice'),
            @($true,$false,$true,'WindowsThirdParty'), @($false,$true,$true,'OfficeThirdParty'), @($true,$true,$true,'All')
        )
        foreach ($mappingCase in $scopeMappingCases) {
            $mapped = ConvertTo-CleanupScanScope -Windows ([bool]$mappingCase[0]) -Office ([bool]$mappingCase[1]) -ThirdParty ([bool]$mappingCase[2])
            if ([string]$mapped -ne [string]$mappingCase[3]) {
                Fail "Ánh xạ hộp tích phạm vi sai: $($mappingCase[0]),$($mappingCase[1]),$($mappingCase[2]) -> $mapped."
            }
        }

        $checklistAst = $gui.Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-CleanupScopeChecklist'
        }, $true)
        if (-not $checklistAst -or $checklistAst.Extent.Text -notmatch 'System\.Windows\.Forms\.CheckBox' -or
            $checklistAst.Extent.Text -notmatch 'Name="Windows";\s*TextKey="cleanup\.scope\.scanWindows"' -or
            $checklistAst.Extent.Text -notmatch 'Name="Office";\s*TextKey="cleanup\.scope\.scanOffice"' -or
            $checklistAst.Extent.Text -notmatch 'Name="ThirdParty";\s*TextKey="cleanup\.scope\.scanThirdParty"') {
            Fail 'Hộp chọn khắc phục chưa có đủ ba ô tích Windows, Office và phần mềm khác.'
        }

        $onlineStartAst = $gui.Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Start-SoftwareCatalogOnlineUpdate'
        }, $true)
        $onlineCompleteAst = $gui.Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Complete-SoftwareCatalogOnlineUpdate'
        }, $true)
        $cleanupScreenAst = $gui.Ast.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Show-CleanupFunctionScreen'
        }, $true)
        if (-not $onlineStartAst -or $onlineStartAst.Extent.Text -notmatch '\[string\]\$ScanScope' -or
            $onlineStartAst.Extent.Text -notmatch '\$script:softwareCatalogAutoScanScope\s*=\s*\$ScanScope' -or
            -not $onlineCompleteAst -or $onlineCompleteAst.Extent.Text -notmatch 'Start-Cleanup\s+-ScanScope\s+\$requestedScanScope' -or
            -not $cleanupScreenAst -or $cleanupScreenAst.Extent.Text -notmatch '"Online"' -or
            $cleanupScreenAst.Extent.Text -notmatch 'Show-LicenseScopeChooser\s+-Mode\s+\$scopeMode' -or
            $cleanupScreenAst.Extent.Text -notmatch 'Start-SoftwareCatalogOnlineUpdate\s+-ScanScope\s+\$selectedScope') {
            Fail 'Luồng Online chưa dùng cùng hộp ba phạm vi và chưa giữ lựa chọn đến bước quét.'
        }
    } catch {
        Fail "Không chạy được fixture ánh xạ ba ô tích phạm vi: $($_.Exception.Message)"
    }

    try {
        if (-not $elevatedBridge -or
            $elevatedBridge.Text -notmatch '(?s)ProcessStartInfo.+?UseShellExecute\s*=\s*\$false.+?EnvironmentVariables\[\$name\].+?\$child\.Start\(\).+?WaitForExit\(\)' -or
            $elevatedBridge.Text -match 'Start-Process\s+@startParameters') {
            Fail 'Cầu nối UAC chưa tạo tiến trình con trực tiếp với khối môi trường TOOL_* tường minh.'
        }
        foreach ($functionName in @('Get-ToolElevatedEnvironmentSnapshot','New-ToolElevatedBootstrapArguments')) {
            $functionAst = $gui.Ast.Find({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
            }, $true)
            if (-not $functionAst) { throw "Missing function: $functionName" }
            Invoke-Expression ("function script:" + $functionName + " " + $functionAst.Body.Extent.Text)
        }
        if ([regex]::Matches($gui.Text, 'New-ToolElevatedBootstrapArguments\s+-BridgeScriptPath\s+\$elevatedBridgeScript\s+-TargetFilePath\s+\$toolPowerShellPath').Count -lt 2) {
            Fail 'Luồng tiến trình quản trị chưa dùng cầu nối môi trường cho cả tác vụ theo dõi và tác vụ tách rời.'
        }
        $bridgeEnvironmentNames = @('TOOL_SECURE_LAUNCH','TOOL_SECURE_RUNTIME_DIR','TOOL_MODULE_ID','TOOL_MODULE_INVOCATION_ID','TOOL_DATA_SCOPE','TOOL_DATA_OWNER_SID')
        $previousBridgeEnvironment = [ordered]@{}
        $bridgeFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-Elevated-Bridge-Fixture-' + [guid]::NewGuid().ToString('N'))
        foreach ($name in $bridgeEnvironmentNames) {
            $previousBridgeEnvironment[$name] = [Environment]::GetEnvironmentVariable($name, [EnvironmentVariableTarget]::Process)
        }
        try {
            $bridgePowerShell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (-not (Test-Path -LiteralPath $bridgePowerShell -PathType Leaf)) { throw "Missing PowerShell: $bridgePowerShell" }
            $bridgeRuntimeRoot = Join-Path $bridgeFixtureRoot 'runtime'
            [void][IO.Directory]::CreateDirectory($bridgeFixtureRoot)
            [void][IO.Directory]::CreateDirectory($bridgeRuntimeRoot)
            $administratorsSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')
            $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
            $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
            $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [Security.AccessControl.InheritanceFlags]::ObjectInherit
            foreach ($protectedDirectory in @($bridgeFixtureRoot,$bridgeRuntimeRoot)) {
                $fixtureAcl = New-Object Security.AccessControl.DirectorySecurity
                $fixtureAcl.SetAccessRuleProtection($true, $false)
                $fixtureAcl.SetOwner($currentUserSid)
                foreach ($sid in @($administratorsSid,$systemSid,$currentUserSid)) {
                    $fixtureAcl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($sid,'FullControl',$inheritance,'None','Allow')))
                }
                Set-Acl -LiteralPath $protectedDirectory -AclObject $fixtureAcl -ErrorAction Stop
            }
            $bridgeFixtureScript = Join-Path $bridgeFixtureRoot 'Tool-ElevatedBridge.ps1'
            $cleanupFixtureScript = Join-Path $bridgeFixtureRoot 'windows-license-compliance-cleanup.ps1'
            Copy-Item -LiteralPath (Join-Path $root 'Tool-ElevatedBridge.ps1') -Destination $bridgeFixtureScript -Force
            Copy-Item -LiteralPath (Join-Path $root 'windows-license-compliance-cleanup.ps1') -Destination $cleanupFixtureScript -Force
            $env:TOOL_SECURE_LAUNCH = '1'
            $env:TOOL_SECURE_RUNTIME_DIR = $bridgeRuntimeRoot
            $env:TOOL_DATA_SCOPE = 'User'
            $env:TOOL_DATA_OWNER_SID = $currentUserSid.Value
            $env:TOOL_MODULE_ID = 'cleanup.scan'
            $env:TOOL_MODULE_INVOCATION_ID = [guid]::NewGuid().ToString('N')
            $bridgeChildArguments = "-NoProfile -ExecutionPolicy RemoteSigned -File `"$cleanupFixtureScript`" -BridgeEnvironmentProbe"
            $bridgeArguments = New-ToolElevatedBootstrapArguments -BridgeScriptPath $bridgeFixtureScript -TargetFilePath $bridgePowerShell -TargetArguments $bridgeChildArguments -HiddenWindow $true

            # Simulate the RunAs broker dropping/replacing the caller environment.
            # The protected bridge must restore the captured values, not inherit these mutations.
            $env:TOOL_SECURE_LAUNCH = '0'
            $env:TOOL_MODULE_ID = 'wrong-module'
            $bridgeProcess = Start-Process -FilePath $bridgePowerShell -ArgumentList $bridgeArguments -WindowStyle Hidden -Wait -PassThru
            if (-not $bridgeProcess -or [int]$bridgeProcess.ExitCode -ne 0) {
                Fail "Cầu nối UAC không khôi phục ngữ cảnh secure-launch cho tiến trình con (exit $([int]$bridgeProcess.ExitCode))."
            }
            $blockedWithoutSecureLaunch = $false
            try {
                [void](New-ToolElevatedBootstrapArguments -BridgeScriptPath $bridgeFixtureScript -TargetFilePath $bridgePowerShell -TargetArguments $bridgeChildArguments)
            } catch {
                $blockedWithoutSecureLaunch = [string]$_.Exception.Message -eq 'ElevatedBridgeSecureLaunchRequired'
            }
            if (-not $blockedWithoutSecureLaunch) { Fail 'Cầu nối UAC không fail-closed khi nguồn gọi thiếu secure launch.' }
        } finally {
            foreach ($name in $bridgeEnvironmentNames) {
                [Environment]::SetEnvironmentVariable($name, $previousBridgeEnvironment[$name], [EnvironmentVariableTarget]::Process)
            }
            if ($bridgeFixtureRoot -and (Test-Path -LiteralPath $bridgeFixtureRoot -PathType Container)) {
                Remove-Item -LiteralPath $bridgeFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    } catch {
        Fail "Không chạy được fixture cầu nối UAC/secure launch: $($_.Exception.Message) | $($_.ScriptStackTrace)"
    }

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
    foreach ($requiredToken in @('Show-LicenseScopeChooser','Show-CleanupScopeChecklist','cleanup.scope.scanWindows','cleanup.scope.scanOffice','cleanup.scope.scanThirdParty','Start-CleanupBackup -Scope $selectedScope','Start-CleanupRestore -Scope $selectedScope','cleanup.report.readyOnDemand','progress.slowTask')) {
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
    foreach ($requiredToken in @('Get-ToolSoftwareInventory','Get-ToolSoftwareAssessments','Get-ToolSoftwareKnownActivationState','Get-ToolSoftwareDeepScanEvidence','Get-ToolSoftwareDeepSystemSnapshot','Get-ToolSoftwareLastDeepScanMetadata','Merge-ToolSoftwareInventoryRecords','Test-ToolSoftwareLikelySystemComponent','CleanupFinding','RemediationEvidenceCount','IsSystemComponent','KnownBadFileHash','DeepSignatureHashMismatch','Update-ToolSoftwareLicenseCatalog','Explicit user consent is required','raw.githubusercontent.com','Catalog URL is outside the HTTPS allowlist',"`$request.Method = 'GET'",'AllowAutoRedirect = $false','ContentLength -gt $MaximumBytes','UploadedInventory=$false','SentLicenseKeys=$false')) {
        if ($softwareInventory.Text -notmatch [regex]::Escape($requiredToken)) { Fail "Mô-đun kiểm kê/danh mục online thiếu ràng buộc an toàn: $requiredToken" }
    }
    if ($softwareInventory.Text -match '(?i)\b(method\s*=\s*["''](?:POST|PUT|PATCH)|uploadfile|invoke-restmethod\b.+-(?:method\s+)?(?:post|put|patch))') {
        Fail 'Mô-đun danh mục phần mềm chứa phương thức tải dữ liệu lên.'
    }
    try {
        . (Join-Path $root 'Tool-SoftwareInventory.ps1')
        $catalogPath = Join-Path $root 'software-license-catalog-v1.0.json'
        $catalogSignaturePath = $catalogPath + '.p7s'
        $trustedBundledCatalog = Import-ToolSoftwareCatalogFile -Path $catalogPath -SignaturePath $catalogSignaturePath -Source 'Bundled' -RequireSignature
        if (-not $trustedBundledCatalog -or -not (Test-ToolSoftwareCatalogTrustedForDecisiveEvidence -Catalog $trustedBundledCatalog)) {
            throw 'Catalogue phần mềm tích hợp chưa mở được bằng chữ ký CMS và signer đã ghim.'
        }
        foreach ($dateFixture in @(
            [pscustomobject]@{ Raw='20260811'; Expected='2026-08-11' },
            [pscustomobject]@{ Raw='20260811112233.000000+420'; Expected='2026-08-11' },
            [pscustomobject]@{ Raw='1786406400'; Expected='2026-08-11' }
        )) {
            if ((ConvertTo-ToolSoftwareInstallDateText $dateFixture.Raw) -ne $dateFixture.Expected) {
                Fail "Ngày cài '$($dateFixture.Raw)' chưa chuẩn hóa thành $($dateFixture.Expected)."
            }
        }
        foreach ($activatorFixture in @(
            'TSforge Activation','Office OHook','MAS_AIO','MAS Activation','Microsoft Activation Scripts',
            'PMAS','PMAS-HWID','Activation Program 1.17','KMS_VL_ALL','Microsoft Toolkit','KMSpico',
            'irm erturk-dev.netlify.app/run | iex','powershell -NoProfile -c "irm https://erturk-dev.netlify.app/run | iex"'
        )) {
            if (-not (Test-ToolSoftwareKnownActivatorText -Text $activatorFixture)) { Fail "Thiếu mẫu activator: $activatorFixture" }
        }
        foreach ($benignActivationFixture in @(
            'Microsoft.Toolkit.Win32.UI.XamlHost.dll','MassTransit Service','PMAScheduler.exe','Activation Program 1.18',
            'irm https://docs-site.netlify.app/runbook | iex','irm https://my-erturk-dev.netlify.app/run | iex',
            'irm https://erturk-dev.netlify.app/runner | iex','irm https://api.example.com/status | ConvertFrom-Json'
        )) {
            if (Test-ToolSoftwareKnownActivatorText -Text $benignActivationFixture) { Fail "Mẫu hợp lệ bị nhận nhầm là activator: $benignActivationFixture" }
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
        $script:StrictActivatorPattern = $script:ToolSoftwareKnownActivatorPattern
        $script:StrictActivationCommandPattern = $script:ToolSoftwareKnownActivationCommandPattern
        if (-not (Test-CleanupKnownActivatorText -Text 'irm erturk-dev.netlify.app/run | iex') -or
            (Test-CleanupKnownActivatorText -Text 'irm https://legitimate-tools.netlify.app/run | iex')) {
            Fail 'Lớp cleanup chưa nhận đúng command erturk-dev hoặc đang bắt nhầm Netlify/PowerShell hợp lệ.'
        }
        $unsignedFixtureCatalog = [pscustomobject]@{
            CatalogSource='Fixture'; CatalogVersion='1.0.0.0'; Products=@([pscustomobject]@{
                Id='unsigned-fixture'; Vendor='Example'; NamePatterns=@('^Raw Catalog App\b'); PublisherPatterns=@('^Example$')
                LicenseModel='Paid'; OfficialUrl='https://example.invalid/'; LicenseDomains=@(); UnauthorizedNamePatterns=@('raw-only-marker')
            })
        }
        $fixtureApp = [pscustomobject]@{
            Id='abbyy-fixture'; Name='ABBYY FineReader PDF by sandyd'; Version='16'; Publisher='ABBYY Development, Inc.'
            InstallLocation=''; RepresentativePath=''; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false
        }
        $assessment = @(Get-ToolSoftwareAssessments -Applications @($fixtureApp) -Catalog $trustedBundledCatalog)
        if ($assessment.Count -ne 1 -or [string]$assessment[0].AssessmentCode -ne 'NonGenuine' -or -not [bool]$assessment[0].ManualEligible -or [string]$assessment[0].RemediationAdapter -ne 'Generic') {
            Fail 'Đánh giá ABBYY tổng quát chưa mở chọn thủ công từ bằng chứng mạnh.'
        }
        $unsignedFixtureApp = [pscustomobject]@{
            Id='unsigned-fixture-app'; Name='Raw Catalog App raw-only-marker'; Version='1'; Publisher='Example'
            InstallLocation=''; RepresentativePath=''; SourceKind='Registry'; SignatureStatus='NotChecked'; SignaturePublisher=''
            IsMicrosoft=$false; IsSystemComponent=$false
        }
        $unsignedAssessment = @(Get-ToolSoftwareAssessments -Applications @($unsignedFixtureApp) -Catalog $unsignedFixtureCatalog)[0]
        if ([string]$unsignedAssessment.CatalogMatchReason -ne 'CatalogUntrusted' -or $unsignedAssessment.CatalogProductId -or
            [string]$unsignedAssessment.LicenseModel -ne 'Unknown' -or [string]$unsignedAssessment.CatalogSource -ne 'UntrustedRejected' -or
            [string]$unsignedAssessment.LicenseModelReason -match '^SignedCatalog:' -or [int]$unsignedAssessment.DecisiveEvidenceCount -ne 0 -or
            [bool]$unsignedAssessment.CleanupFinding -or [bool]$unsignedAssessment.ManualEligible -or [bool]$unsignedAssessment.AutoEligible -or
            @($unsignedAssessment.Evidence | Where-Object { $_.Code -eq 'CatalogUnauthorizedName' }).Count -ne 0) {
            Fail 'Catalogue raw/không ký vẫn ảnh hưởng phân loại, bằng chứng quyết định hoặc quyền khắc phục.'
        }
        $lowAssessmentApp = [pscustomobject]@{
            Id='unknown-low-fixture'; Name='Unknown clean fixture'; Version='1'; Publisher='Example'
            InstallLocation=''; RepresentativePath=''; SourceKind='Registry'; SignatureStatus='NotChecked'; IsMicrosoft=$false
        }
        $lowAssessment = @(Get-ToolSoftwareAssessments -Applications @($lowAssessmentApp) -Catalog $null)[0]
        if ([string]$lowAssessment.Confidence -ne 'Low' -or [bool]$lowAssessment.CleanupFinding -or
            [bool]$lowAssessment.ManualEligible -or [bool]$lowAssessment.AutoEligible) {
            Fail 'Đánh giá Low confidence vẫn mở điều kiện khắc phục.'
        }
        $unlinkedDecisiveEvidence = [pscustomobject]@{
            Code='InventoryObservation'; Type='Fixture'; Source='Fixture'; ApplicationId='unknown-low-fixture'
            VendorScope='Example'; Strength='Conclusive'; EvidenceGroup='Inventory'; Decisive=$true; Detail='fixture only'
        }
        $unlinkedAssessment = @(Get-ToolSoftwareAssessments -Applications @($lowAssessmentApp) -Catalog $null -ExternalEvidence @($unlinkedDecisiveEvidence))[0]
        if ([string]$unlinkedAssessment.AssessmentCode -ne 'NonGenuine' -or [int]$unlinkedAssessment.RemediationEvidenceCount -ne 0 -or
            [bool]$unlinkedAssessment.CleanupFinding -or [bool]$unlinkedAssessment.ManualEligible) {
            Fail 'Bằng chứng quyết định không gắn activator/tampering vẫn tạo finding khắc phục.'
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
            Code='KnownActivatorFileArtifact'; Type='FileArtifact'; Source='FileArtifact'; Name='known-activator.zip'
            Location=$rescanArtifact; ApplicationId='rescan-app'; VendorScope='Example'; Strength='Strong'
            EvidenceGroup='ActivatorArtifact'; Decisive=$true; Detail='fixture'
        }
        $beforeCleanup = @(Get-ToolSoftwareAssessments -Applications @($rescanApp) -Catalog $trustedBundledCatalog -ExternalEvidence @($rescanEvidence))[0]
        $beforeCandidates = @(Get-ThirdPartyLicenseCandidates -Applications @($beforeCleanup) -Evidence @($rescanEvidence))
        if (-not [bool]$beforeCleanup.CleanupFinding -or $beforeCandidates.Count -ne 1 -or
            @($beforeCandidates[0].PlanItems | Where-Object { $_.Type -eq 'File' -and $_.Location -eq $rescanArtifact }).Count -ne 1) {
            Fail 'Fixture trước làm sạch chưa tạo đúng finding/candidate cho FileArtifact.'
        }
        [IO.File]::Delete($rescanArtifact)
        $afterCleanup = @(Get-ToolSoftwareAssessments -Applications @($rescanApp) -Catalog $trustedBundledCatalog -ExternalEvidence @())[0]
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
        $knownActivatorExe = Join-Path $tamperedRoot 'KMSPico.exe'
        [IO.File]::WriteAllText($cleanExe, 'clean-fixture', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($cleanDocumentation, 'documentation fixture only', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($suspiciousExe, 'suspicious-fixture-main', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($suspiciousArtifact, 'fixture only', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($tamperedExe, 'known-bad-fixture', (New-Object Text.UTF8Encoding($false)))
        [IO.File]::WriteAllText($knownActivatorExe, 'known-activator-fixture', (New-Object Text.UTF8Encoding($false)))
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
        if ([string]$suspiciousResult.AssessmentCode -ne 'Suspicious' -or [int]$suspiciousResult.DecisiveEvidenceCount -ne 0 -or [bool]$suspiciousResult.CleanupFinding -or
            @($suspiciousResult.Evidence | Where-Object { $_.Code -eq 'SuspiciousArtifactName' }).Count -ne 1) {
            Fail 'Tên crack tổng quát phải chỉ tạo trạng thái Suspicious để xem xét, không được tự kết luận NonGenuine hoặc đưa vào khắc phục.'
        }
        if ([string]$tamperedResult.AssessmentCode -ne 'NonGenuine' -or [int]$tamperedResult.DecisiveEvidenceCount -lt 1 -or
            @($tamperedResult.Evidence | Where-Object { $_.Code -eq 'KnownActivatorArtifact' -and $_.Decisive }).Count -lt 1 -or
            @($tamperedResult.Evidence | Where-Object { $_.Code -eq 'KnownBadFileHash' }).Count -ne 0 -or
            [string]$tamperedResult.CatalogMatchReason -ne 'CatalogUntrusted') {
            Fail 'Quét sâu chưa ưu tiên dấu vết activator tích hợp hoặc vẫn tin hash từ catalogue raw.'
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

        [IO.File]::Delete($knownActivatorExe)

        $untrustedCatalog = [pscustomobject]@{
            CatalogSource='OnlineCache'; CatalogVersion='99.0.0.0'; CatalogSha256=('A' * 64); CatalogSignatureValid=$true
            DeepScan=[pscustomobject]@{ KnownActivatorNamePatterns=@(); SuspiciousArtifactNamePatterns=@(); KnownBadSha256=@() }
            Products=$deepCatalog.Products
        }
        $untrustedAssessment = @(Get-ToolSoftwareAssessments -Applications @($deepApps[2]) -Catalog $untrustedCatalog -DeepScan `
            -DeepScanMaximumDurationSeconds 45 -DeepScanMaximumSignatureChecks 20 -DeepScanMaximumHashChecks 20)[0]
        if ([string]$untrustedAssessment.AssessmentCode -eq 'NonGenuine' -or [int]$untrustedAssessment.DecisiveEvidenceCount -ne 0 -or
            [string]$untrustedAssessment.CatalogMatchReason -ne 'CatalogUntrusted' -or
            [string]$untrustedAssessment.CatalogSource -ne 'UntrustedRejected' -or
            @($untrustedAssessment.Evidence | Where-Object { $_.Code -eq 'KnownBadFileHash' }).Count -ne 0) {
            Fail 'Catalog tự khai báo nguồn/hash/chữ ký vẫn ảnh hưởng kết luận hoặc hash quét sâu.'
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
        $catalogPath = Join-Path $root 'software-license-catalog-v1.0.json'
        $catalogSignaturePath = $catalogPath + '.p7s'
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $catalogIds = @($catalog.Products | ForEach-Object { [string]$_.Id })
        if ([string]$catalog.CatalogVersion -ne '1.4.0.0' -or [string]$catalog.GeneratedAtUtc -ne '2026-08-17T00:00:00Z' -or
            $catalogIds.Count -lt 77 -or @($catalogIds | Select-Object -Unique).Count -ne $catalogIds.Count) {
            Fail 'Catalogue phần mềm v4.8 chưa đạt 1.4.0.0 / ngày phát hành / 77 quy tắc duy nhất.'
        }
        foreach ($requiredCatalogId in @('iobit-driver-booster','winrar','adobe-creative-cloud-paid','autodesk-commercial','commercial-pdf-editors','internet-download-manager','mathworks-matlab-simulink','wiris-mathtype','microsoft-visual-studio-community','microsoft-visual-studio-paid')) {
            if ($catalogIds -notcontains $requiredCatalogId) { Fail "Catalogue phần mềm thiếu quy tắc: $requiredCatalogId" }
        }
        $blankNamePatternCatalog = ($catalog | ConvertTo-Json -Depth 64 | ConvertFrom-Json)
        $blankNamePatternCatalog.Products[0].NamePatterns = @(' ')
        if (Test-ToolSoftwareCatalogObject -Catalog $blankNamePatternCatalog) {
            Fail 'Schema catalogue vẫn nhận NamePatterns rỗng/trắng.'
        }
        $blankDomainPatternCatalog = ($catalog | ConvertTo-Json -Depth 64 | ConvertFrom-Json)
        $blankDomainPatternCatalog.Products[0].LicenseDomains = @('')
        if (Test-ToolSoftwareCatalogObject -Catalog $blankDomainPatternCatalog) {
            Fail 'Schema catalogue vẫn nhận LicenseDomains rỗng.'
        }
        $trustedBundledCatalog = Import-ToolSoftwareCatalogFile -Path $catalogPath -SignaturePath $catalogSignaturePath -Source 'Bundled' -RequireSignature
        if (-not $trustedBundledCatalog -or -not [bool]$trustedBundledCatalog.CatalogSignatureValid -or
            [string]$trustedBundledCatalog.CatalogVersion -ne '1.4.0.0') {
            Fail 'Catalogue phần mềm tích hợp chưa mở được bằng chữ ký CMS và signer đã ghim.'
        }
        $forgedCatalog = (Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json)
        $forgedCatalog | Add-Member -NotePropertyName CatalogSource -NotePropertyValue 'Bundled' -Force
        $forgedCatalog | Add-Member -NotePropertyName CatalogSha256 -NotePropertyValue ([string]$trustedBundledCatalog.CatalogSha256) -Force
        $forgedCatalog | Add-Member -NotePropertyName CatalogSignatureValid -NotePropertyValue $true -Force
        if (Test-ToolSoftwareCatalogTrustedForDecisiveEvidence -Catalog $forgedCatalog) {
            Fail 'Object catalogue tự khai báo metadata chữ ký được tin mà không đi qua import CMS.'
        }
        $forgedCatalogApp = New-ToolSoftwareInventoryRecord -Name 'Adobe Photoshop 2025' -Version '26.0' -Publisher 'Adobe Inc.' -InstallLocation 'C:\Fixture\ForgedCatalog' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $forgedCatalogAssessment = @(Get-ToolSoftwareAssessments -Applications @($forgedCatalogApp) -Catalog $forgedCatalog)[0]
        if ($forgedCatalogAssessment.CatalogProductId -or [string]$forgedCatalogAssessment.CatalogMatchReason -ne 'CatalogUntrusted' -or
            [string]$forgedCatalogAssessment.LicenseModelReason -match '^SignedCatalog:' -or [bool]$forgedCatalogAssessment.ManualEligible) {
            Fail 'Object catalogue giả metadata vẫn tạo phân loại SignedCatalog hoặc quyền khắc phục.'
        }
        $mutatedSignedCatalog = Import-ToolSoftwareCatalogFile -Path $catalogPath -SignaturePath $catalogSignaturePath -Source 'Bundled' -RequireSignature
        $mutatedSignedCatalog.Products[0].LicenseModel = 'Unknown'
        if (Test-ToolSoftwareCatalogTrustedForDecisiveEvidence -Catalog $mutatedSignedCatalog) {
            Fail 'Catalogue đã import nhưng bị sửa trong bộ nhớ vẫn được tin.'
        }
        $tamperedCatalogPath = Join-Path ([IO.Path]::GetTempPath()) ('Tool-Software-Catalog-Tampered-' + [guid]::NewGuid().ToString('N') + '.json')
        try {
            $tamperedBytes = [IO.File]::ReadAllBytes($catalogPath)
            $tamperedBytes[$tamperedBytes.Length - 2] = $tamperedBytes[$tamperedBytes.Length - 2] -bxor 1
            [IO.File]::WriteAllBytes($tamperedCatalogPath, $tamperedBytes)
            if (Import-ToolSoftwareCatalogFile -Path $tamperedCatalogPath -SignaturePath $catalogSignaturePath -Source 'Bundled' -RequireSignature) {
                Fail 'Catalogue phần mềm bị sửa byte vẫn vượt qua kiểm tra chữ ký.'
            }
        } finally {
            if ($tamperedCatalogPath -and (Test-Path -LiteralPath $tamperedCatalogPath -PathType Leaf)) {
                Remove-Item -LiteralPath $tamperedCatalogPath -Force -ErrorAction SilentlyContinue
            }
        }

        $classificationApps = @(
            (New-ToolSoftwareInventoryRecord -Name 'IObit Driver Booster 13 Pro' -Version '13.0' -Publisher 'IObit' -InstallLocation 'C:\Fixture\DriverBooster' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'MathType 7' -Version '7.8' -Publisher 'WIRIS' -InstallLocation 'C:\Fixture\MathType' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'Wondershare PDFelement' -Version '11.0' -Publisher 'Wondershare' -InstallLocation 'C:\Fixture\PDFelement' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'IDM 6.42' -Version '6.42' -Publisher 'Tonec' -InstallLocation 'C:\Fixture\IDM' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'Zoom Workplace' -Version '6.0' -Publisher 'Zoom Video Communications, Inc.' -InstallLocation 'C:\Fixture\Zoom' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'MATLAB Runtime R2025a' -Version '25.1' -Publisher 'MathWorks' -InstallLocation 'C:\Fixture\MATLABRuntime' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'Microsoft Visual Studio Community 2022' -Version '17.0' -Publisher 'Microsoft Corporation' -InstallLocation 'C:\Fixture\VSCommunity' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery),
            (New-ToolSoftwareInventoryRecord -Name 'Microsoft Visual Studio Professional 2022' -Version '17.0' -Publisher 'Microsoft Corporation' -InstallLocation 'C:\Fixture\VSProfessional' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery)
        )
        $classificationResults = @(Get-ToolSoftwareAssessments -Applications $classificationApps -Catalog $trustedBundledCatalog)
        $iobitResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'iobit-driver-booster' })
        $mathTypeResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'wiris-mathtype' })
        $pdfResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'commercial-pdf-editors' })
        $idmResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'internet-download-manager' })
        $zoomResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'communication-freemium' })
        $matlabRuntimeResult = @($classificationResults | Where-Object { $_.Name -eq 'MATLAB Runtime R2025a' })
        $visualStudioCommunityResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'microsoft-visual-studio-community' })
        $visualStudioPaidResult = @($classificationResults | Where-Object { $_.CatalogProductId -eq 'microsoft-visual-studio-paid' })
        if ($iobitResult.Count -ne 1 -or [string]$iobitResult[0].LicenseModel -ne 'Freemium' -or [bool]$iobitResult[0].IsSystemComponent) {
            Fail 'IObit Driver Booster vẫn bị bỏ sót hoặc phân loại nhầm thành driver hệ thống.'
        }
        if ($mathTypeResult.Count -ne 1 -or [string]$mathTypeResult[0].LicenseModel -ne 'Subscription') {
            Fail 'MathType chưa được nhận diện đúng bằng catalogue.'
        }
        if ($pdfResult.Count -ne 1 -or [string]$pdfResult[0].LicenseModel -ne 'Paid' -or [string]$pdfResult[0].CatalogLicenseModel -ne 'Commercial') { Fail 'PDF editor thương mại chưa được nhận diện và chuẩn hóa đúng bằng catalogue.' }
        if ($idmResult.Count -ne 1 -or [string]$idmResult[0].LicenseModel -ne 'Trial' -or [string]$idmResult[0].CatalogLicenseModel -ne 'Trialware') { Fail 'Tên ngắn IDM chưa được nhận diện và chuẩn hóa đúng bằng catalogue.' }
        if ($zoomResult.Count -ne 1 -or [string]$zoomResult[0].LicenseModel -ne 'Freemium') { Fail 'Zoom Workplace chưa đi vào quy tắc Freemium cụ thể.' }
        if ($matlabRuntimeResult.Count -ne 1 -or [string]$matlabRuntimeResult[0].CatalogProductId -ne 'mathworks-matlab-simulink' -or
            [string]$matlabRuntimeResult[0].LicenseModel -ne 'Paid' -or [bool]$matlabRuntimeResult[0].IsSystemComponent) {
            Fail 'MATLAB Runtime vẫn bị quy tắc Driver tổng quát chiếm trước.'
        }
        if ($visualStudioCommunityResult.Count -ne 1 -or [string]$visualStudioCommunityResult[0].LicenseModel -ne 'Free' -or
            $visualStudioPaidResult.Count -ne 1 -or [string]$visualStudioPaidResult[0].LicenseModel -ne 'Paid') {
            Fail 'Visual Studio Community/Professional chưa được tách mô hình giấy phép fail-closed.'
        }

        $publisherUnavailableApp = New-ToolSoftwareInventoryRecord -Name 'Adobe Photoshop 2025' -Version '26.0' -Publisher '' -InstallLocation 'C:\Fixture\PublisherUnavailable' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $publisherUnavailableMatch = Find-ToolSoftwareCatalogMatch -Application $publisherUnavailableApp -Catalog $trustedBundledCatalog
        if ($publisherUnavailableMatch.Product -or [string]$publisherUnavailableMatch.Reason -ne 'NameMatchedPublisherUnavailable') {
            Fail 'Quy tắc yêu cầu publisher vẫn match khi cả Registry và Authenticode publisher đều thiếu.'
        }
        $ambiguousApp = New-ToolSoftwareInventoryRecord -Name 'Telegram Desktop Tailscale' -Version '1' -Publisher '' -InstallLocation 'C:\Fixture\AmbiguousCatalog' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $ambiguousMatch = Find-ToolSoftwareCatalogMatch -Application $ambiguousApp -Catalog $trustedBundledCatalog
        if ($ambiguousMatch.Product -or [string]$ambiguousMatch.Reason -ne 'AmbiguousCatalogMatch' -or @($ambiguousMatch.CandidateProductIds).Count -lt 2) {
            Fail 'Nhiều quy tắc catalogue cùng match chưa bị từ chối vì mơ hồ.'
        }

        $systemRemediationApp = [pscustomobject]@{
            Id='system-remediation-invariant'; Name='NVIDIA KMSPico Tool'; Version='1'; Publisher='NVIDIA Corporation'
            InstallLocation=''; RepresentativePath=''; SourceKind='Registry'; SignatureStatus='NotChecked'; SignaturePublisher=''
            IsMicrosoft=$false; IsSystemComponent=$false; SystemComponentReason=''
        }
        $systemRemediationAssessment = @(Get-ToolSoftwareAssessments -Applications @($systemRemediationApp) -Catalog $trustedBundledCatalog)[0]
        if (-not [bool]$systemRemediationAssessment.IsSystemComponent -or [string]$systemRemediationAssessment.CatalogLicenseModel -ne 'Driver' -or
            [bool]$systemRemediationAssessment.CleanupFinding -or [bool]$systemRemediationAssessment.RemediationSupported -or
            [bool]$systemRemediationAssessment.ManualEligible -or [bool]$systemRemediationAssessment.AutoEligible -or
            -not [string]::IsNullOrWhiteSpace([string]$systemRemediationAssessment.RemediationAdapter)) {
            Fail 'SystemComponent được catalog xác định sau discovery vẫn lộ cleanup/remediation.'
        }

        $activationFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('Tool-WinRAR-State-Fixture-' + [guid]::NewGuid().ToString('N'))
        $previousAppData = [string]$env:APPDATA
        $previousProgramData = [string]$env:ProgramData
        try {
            $winRarInstallRoot = Join-Path $activationFixtureRoot 'WinRAR'
            $env:APPDATA = Join-Path $activationFixtureRoot 'AppData'
            $env:ProgramData = Join-Path $activationFixtureRoot 'ProgramData'
            foreach ($directory in @($winRarInstallRoot,$env:APPDATA,$env:ProgramData)) { [void][IO.Directory]::CreateDirectory($directory) }
            $winRarProduct = @($trustedBundledCatalog.Products | Where-Object { [string]$_.Id -eq 'winrar' })[0]
            if ([string]$winRarProduct.OfficialUrl -ne 'https://www.rarlab.com/license.htm') {
                Fail 'WinRAR chưa dẫn trực tiếp tới EULA chính thức.'
            }
            $winRarApp = New-ToolSoftwareInventoryRecord -Name 'WinRAR 7.11' -Version '7.11' -Publisher 'win.rar GmbH' -InstallLocation $winRarInstallRoot -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
            if ([string](Get-ToolSoftwareKnownActivationState -Application $winRarApp -CatalogProduct $winRarProduct) -ne 'Unactivated') {
                Fail 'WinRAR không có rarreg.key chưa được xác nhận là chưa kích hoạt.'
            }
            $rarRegPath = Join-Path $winRarInstallRoot 'rarreg.key'
            [IO.File]::WriteAllText($rarRegPath, 'fixture-license', (New-Object Text.UTF8Encoding($false)))
            if ([string](Get-ToolSoftwareKnownActivationState -Application $winRarApp -CatalogProduct $winRarProduct) -ne 'LocalLicenseArtifactPresent') {
                Fail 'WinRAR có rarreg.key nhưng đầu dò không ghi nhận dấu vết giấy phép cục bộ một cách bảo thủ.'
            }
            $registeredWinRarAssessment = @(Get-ToolSoftwareAssessments -Applications @($winRarApp) -Catalog $trustedBundledCatalog)[0]
            if ([bool]$registeredWinRarAssessment.CleanupFinding -or [bool]$registeredWinRarAssessment.ManualEligible -or
                [bool]$registeredWinRarAssessment.AutoEligible -or [string]$registeredWinRarAssessment.RemediationImpact -ne 'NoChangeProposed') {
                Fail 'WinRAR có rarreg.key nhưng không có bằng chứng lạm dụng vẫn bị đưa vào khắc phục.'
            }
            [IO.File]::Delete($rarRegPath)
            $winRarAssessment = @(Get-ToolSoftwareAssessments -Applications @($winRarApp) -Catalog $trustedBundledCatalog)[0]
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
        if ($officeMergedFixture.Count -ne 2) {
            Fail 'Hai patch build Office khác nhau bị gộp chỉ vì cùng họ phiên bản.'
        }
        $halRecordA = New-ToolSoftwareInventoryRecord -Name 'ASUS Ambient HAL' -Version '7.4.0.0' -Publisher 'ASUSTeK COMPUTER INC.' -InstallLocation 'C:\Program Files\ASUS\HAL64' -Architecture '64-bit' -SourceKind 'Registry' -SourceDetail 'HKLM64' -SkipSignature -SkipExecutableDiscovery
        $halRecordB = New-ToolSoftwareInventoryRecord -Name 'ASUS Ambient HAL' -Version '7.4.0.0' -Publisher 'ASUSTeK COMPUTER INC.' -InstallLocation 'C:\Program Files (x86)\ASUS\HAL32' -Architecture '32-bit' -SourceKind 'Registry' -SourceDetail 'HKLM32' -SkipSignature -SkipExecutableDiscovery
        $halMergedFixture = @(Merge-ToolSoftwareInventoryRecords -Records @($halRecordA,$halRecordB))
        if ($halMergedFixture.Count -ne 2 -or @($halMergedFixture | Where-Object { -not [bool]$_.IsSystemComponent }).Count -ne 0) {
            Fail 'Hai cài đặt Registry song song khác kiến trúc/vị trí bị gộp nhầm.'
        }
        $registryParallelA = New-ToolSoftwareInventoryRecord -Name 'Parallel Registry App' -Version '1.0' -Publisher 'Example Corp' -InstallLocation 'C:\Program Files\ParallelApp' -RegistryPath 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ParallelA' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $registryParallelB = New-ToolSoftwareInventoryRecord -Name 'Parallel Registry App' -Version '1.0' -Publisher 'Example Corp' -InstallLocation 'C:\Program Files\ParallelApp' -RegistryPath 'HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\ParallelB' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        if (@(Merge-ToolSoftwareInventoryRecords -Records @($registryParallelA,$registryParallelB)).Count -ne 2) {
            Fail 'Hai uninstall Registry path riêng biệt bị gộp dù có thể là cài đặt song song.'
        }
        $patchRecordA = New-ToolSoftwareInventoryRecord -Name 'Patch Parallel App' -Version '1.2.3.4' -Publisher 'Example Corp' -InstallLocation 'C:\Program Files\PatchParallel' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        $patchRecordB = New-ToolSoftwareInventoryRecord -Name 'Patch Parallel App' -Version '1.2.3.9' -Publisher 'Example Corp' -InstallLocation 'C:\Program Files\PatchParallel' -SourceKind 'Registry' -SourceDetail 'HKLM' -SkipSignature -SkipExecutableDiscovery
        if (@(Merge-ToolSoftwareInventoryRecords -Records @($patchRecordA,$patchRecordB)).Count -ne 2) {
            Fail 'Hai patch version đầy đủ khác nhau bị gộp chỉ vì cùng ba thành phần đầu.'
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
