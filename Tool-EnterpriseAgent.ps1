<#
    Tool v4.6 workstation agent.
    It is intentionally a one-shot process so the GUI or Task Scheduler can
    invoke it without leaving an unmanaged background service behind.
#>
[CmdletBinding()]
param(
    [switch]$NoReport,
    [switch]$NoJob,
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
try {
    . (Join-Path $baseDir "Tool-Runtime.ps1")
    . (Join-Path $baseDir "Tool-ReportSchema.ps1")
    . (Join-Path $baseDir "Tool-Enterprise.ps1")
    . (Join-Path $baseDir "Tool-OfflinePolicy.ps1")
    [void](Assert-ToolNativeArchitecture)
    if (-not (Test-ToolEnterpriseNetworkActionAllowed)) { throw (Get-ToolEnterpriseText "enterpriseAgent.error.networkBlocked") }
} catch {
    [Console]::Error.WriteLine([string]$_.Exception.Message)
    exit 12
}

function Write-ToolEnterpriseAgentEvent {
    param([Parameter(Mandatory = $true)][string]$Event, [string]$Message = "", [AllowNull()][object]$Data = $null)
    try { Write-ToolEnterpriseAudit -Scope Client -Event $Event -Message $Message -Data $Data } catch {}
}

function Get-ToolEnterpriseAgentReport {
    param([Parameter(Mandatory = $true)][string]$ClientId)
    return (Get-ToolEnterpriseLicenseSnapshot -ClientId $ClientId)
}

function Invoke-ToolEnterpriseAgentOnce {
    $paths = Initialize-ToolEnterpriseStorage
    $config = Get-ToolEnterpriseClientConfig
    if (-not $config -or -not [bool]$config.Enrolled) {
        throw (Get-ToolEnterpriseText "enterpriseAgent.error.notEnrolled")
    }
    $clientId = [string]$config.ClientId
    $summary = [ordered]@{
        ClientId=$clientId; Queued=0; Sent=0; JobStatus="None"; Message=""
    }

    try { $summary.Sent = [int](Flush-ToolEnterpriseOutbox) } catch {
        $summary.Message = ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 800
        Write-ToolEnterpriseAgentEvent -Event "Outbox.FlushFailed" -Message $summary.Message
    }

    $sendReport = (-not $NoReport) -and ($Force -or [bool]$config.AutoSend)
    if ($sendReport) {
        $report = Get-ToolEnterpriseAgentReport -ClientId $clientId
        try {
            [void](Send-ToolEnterpriseReport -Report $report -QueueOnFailure)
            $summary.Sent++
            Write-ToolEnterpriseAgentEvent -Event "Report.Sent" -Message (Get-ToolEnterpriseText "enterpriseAgent.audit.reportSent")
        } catch {
            $summary.Queued++
            $summary.Message = ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 800
            Write-ToolEnterpriseAgentEvent -Event "Report.SendFailed" -Message $summary.Message
        }
    }

    if (-not $NoJob) {
        try {
            $poll = Get-ToolEnterpriseClientJob
            if ($poll -and [bool]$poll.HasJob -and $poll.JobEnvelope) {
                $secret = Get-ToolEnterpriseSecret -Path $paths.ClientSecret
                try {
                    $jobOpened = Open-ToolEnterpriseEnvelope -Secret $secret -ExpectedContext ("job:{0}:{1}" -f $clientId, [string]$poll.JobId) -Envelope $poll.JobEnvelope
                    $job = $jobOpened.Payload
                } finally { [Array]::Clear($secret, 0, $secret.Length) }
                $result = Invoke-ToolEnterpriseLicenseJob -Job $job -AllowRemoteLicenseChanges ([bool]$config.AllowRemoteLicenseChanges)
                $summary.JobStatus = [string]$result.Status
                try {
                    [void](Send-ToolEnterpriseJobResult -Result $result)
                    Write-ToolEnterpriseAgentEvent -Event "Job.ResultSent" -Message (Get-ToolEnterpriseText "enterpriseAgent.audit.jobResultSent") -Data ([ordered]@{
                        JobId=$result.JobId; Operation=$result.Operation; Status=$result.Status; ExitCode=$result.ExitCode; ProductKeyLast5=$result.ProductKeyLast5
                    })
                } catch {
                    $summary.Message = ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 800
                    Write-ToolEnterpriseAgentEvent -Event "Job.ResultSendFailed" -Message $summary.Message -Data ([ordered]@{ JobId=$result.JobId })
                }
                # A job may change the license state, therefore send a fresh
                # inventory after the action (or queue it when the route is
                # temporarily unavailable).
                if ($sendReport) {
                    $afterReport = Get-ToolEnterpriseAgentReport -ClientId $clientId
                    try { [void](Send-ToolEnterpriseReport -Report $afterReport -QueueOnFailure) } catch {}
                }
            }
        } catch {
            $summary.Message = ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 800
            Write-ToolEnterpriseAgentEvent -Event "Job.PollFailed" -Message $summary.Message
        }
    }
    return [pscustomobject]$summary
}

function Write-ToolEnterpriseAgentResultFile {
    param([Parameter(Mandatory = $true)][object]$Value, [switch]$ErrorResult)
    try {
        $paths = Initialize-ToolEnterpriseStorage
        $path = if ($ErrorResult) { [string]$paths.ClientAgentError } else { [string]$paths.ClientAgentResult }
        Write-ToolEnterpriseJson -Path $path -Value $Value
    } catch {}
}

$created = $false
$mutex = New-Object Threading.Mutex($false, "Global\ThanhViet.ToolKiemTra.v4.6.EnterpriseAgent", [ref]$created)
if (-not $created) {
    $mutex.Dispose()
    [Console]::Error.WriteLine((Get-ToolEnterpriseText "enterpriseAgent.error.alreadyRunning"))
    exit 11
}
try {
    $agentPaths = Initialize-ToolEnterpriseStorage
    foreach ($stalePath in @($agentPaths.ClientAgentResult,$agentPaths.ClientAgentError)) {
        if (Test-Path -LiteralPath $stalePath -PathType Leaf) { Remove-Item -LiteralPath $stalePath -Force -ErrorAction SilentlyContinue }
    }
    $result = Invoke-ToolEnterpriseAgentOnce
    Write-ToolEnterpriseAgentEvent -Event "Agent.Completed" -Message (Get-ToolEnterpriseText "enterpriseAgent.audit.completed") -Data ([ordered]@{
        Sent=$result.Sent; Queued=$result.Queued; JobStatus=$result.JobStatus
    })
    Write-ToolEnterpriseAgentResultFile -Value ([ordered]@{
        SchemaVersion=$script:ToolEnterpriseSchemaVersion; ToolVersion=$script:ToolEnterpriseToolVersion
        Success=$true; ExitCode=0; CompletedAtUtc=[DateTime]::UtcNow.ToString('o')
        ClientId=[string]$result.ClientId; Sent=[int]$result.Sent; Queued=[int]$result.Queued
        JobStatus=[string]$result.JobStatus; Message=[string]$result.Message
    })
    $result | ConvertTo-Json -Depth 8 -Compress | Write-Output
    exit 0
} catch {
    $message = ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 1200
    Write-ToolEnterpriseAgentEvent -Event "Agent.Failed" -Message $message
    Write-ToolEnterpriseAgentResultFile -ErrorResult -Value ([ordered]@{
        SchemaVersion=$script:ToolEnterpriseSchemaVersion; ToolVersion=$script:ToolEnterpriseToolVersion
        Success=$false; ExitCode=1; CompletedAtUtc=[DateTime]::UtcNow.ToString('o'); Message=$message
    })
    [Console]::Error.WriteLine($message)
    exit 1
} finally {
    try { $mutex.ReleaseMutex() } catch {}
    $mutex.Dispose()
}
