$script:ToolSafetyPolicySchemaVersion = "1.0"
$script:ToolSafetyPolicyToolVersion = "4.6"

function Get-ToolRegistryValueRestorePolicy {
    $windowsSppPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
    $officeSppPath = "HKLM:\SOFTWARE\Microsoft\OfficeSoftwareProtectionPlatform"
    $windowsSppPolicyPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\CurrentVersion\Software Protection Platform"
    $kmsNames = @(
        "KeyManagementServiceName",
        "KeyManagementServicePort",
        "KeyManagementServiceLookupDomain",
        "DisableDnsPublishing",
        "KeyManagementServiceHostCaching",
        "DiscoveredKeyManagementServiceName",
        "DiscoveredKeyManagementServicePort"
    )

    return @(
        [pscustomobject][ordered]@{ Path=$windowsSppPath; AllowedValueNames=@($kmsNames); Purpose="WindowsKmsConfiguration" },
        [pscustomobject][ordered]@{ Path=$officeSppPath; AllowedValueNames=@($kmsNames); Purpose="OfficeKmsConfiguration" },
        [pscustomobject][ordered]@{ Path=$windowsSppPolicyPath; AllowedValueNames=@("NoGenTicket"); Purpose="WindowsDigitalLicensePolicy" }
    )
}

function Get-ToolAllowedRegistryValueNames {
    param([Parameter(Mandatory = $true)][string]$Path)
    $entry = Get-ToolRegistryValueRestorePolicy | Where-Object {
        [string]::Equals([string]$_.Path, $Path, [StringComparison]::OrdinalIgnoreCase)
    } | Select-Object -First 1
    if (-not $entry) { return @() }
    return @($entry.AllowedValueNames)
}

function Test-ToolRegistryValueRestoreAllowed {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ValueName
    )
    $allowedNames = @(Get-ToolAllowedRegistryValueNames -Path $Path)
    return [bool]($allowedNames -contains $ValueName)
}

function Get-ToolScanSourceServicePolicy {
    return @(
        [pscustomobject][ordered]@{ Name="winmgmt"; DisplayName="WMI/CIM"; AllowStart=$true; AllowStartupTypeChange=$false },
        [pscustomobject][ordered]@{ Name="Schedule"; DisplayName="Task Scheduler"; AllowStart=$true; AllowStartupTypeChange=$false },
        [pscustomobject][ordered]@{ Name="sppsvc"; DisplayName="Software Protection"; AllowStart=$true; AllowStartupTypeChange=$false }
    )
}

function Get-ToolSafetyPolicyMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = [string]$script:ToolSafetyPolicySchemaVersion
        ToolVersion = [string]$script:ToolSafetyPolicyToolVersion
        RegistryValuePolicyCount = [int]@(Get-ToolRegistryValueRestorePolicy).Count
        ScanServicePolicyCount = [int]@(Get-ToolScanSourceServicePolicy).Count
        StartupTypeChangesAllowedByQuickRepair = $false
    }
}
