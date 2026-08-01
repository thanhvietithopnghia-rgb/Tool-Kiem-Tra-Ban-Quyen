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
    if ([string]$metadata.SchemaVersion -ne '1.0' -or [string]$metadata.ToolVersion -ne '4.4') { Fail 'Metadata safety policy sai phiên bản.' }
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
}

if ($gui) {
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
                [pscustomobject]@{ Id='history'; Type='History'; Kind='DefenderEvent'; Location='Event 1116' }
            )
            $autoSelected = @(& $autoSafeFilter -CleanupItems $autoFixture)
            $autoIds = @($autoSelected | ForEach-Object { [string]$_.Id })
            if ($autoSelected.Count -ne 3 -or $autoIds -notcontains 'win-kms' -or $autoIds -notcontains 'office-kms' -or $autoIds -notcontains 'nogen') {
                Fail 'Bộ lọc tự động không chọn đúng ba cấu hình Registry allowlist.'
            }
            if ($autoIds -contains 'wrong-path' -or $autoIds -contains 'license' -or $autoIds -contains 'file' -or $autoIds -contains 'history') {
                Fail 'Bộ lọc tự động đã chọn mục ngoài Registry allowlist.'
            }
        } catch {
            Fail "Không chạy được fixture tự động làm sạch an toàn: $($_.Exception.Message)"
        }
    }
    if ($gui.Text -notmatch 'Start-CleanupDeep\s+-CleanupItems.+-AutomaticSafeMode' -or $gui.Text -notmatch 'Confirm-AutomaticSafeCleanup') {
        Fail 'Luồng tự động chưa bắt buộc xem trước/xác nhận bằng bộ lọc an toàn.'
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
Write-Host 'VERIFY-SAFETY-REGRESSIONS: OK (registry policy + auto-safe cleanup + rollback + Office multi-SKU + native paths)' -ForegroundColor Green
exit 0
