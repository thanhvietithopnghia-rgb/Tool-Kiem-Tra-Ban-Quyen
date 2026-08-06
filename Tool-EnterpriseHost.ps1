<#
    Tool v4.6 enterprise server

    The host is deliberately a small HTTP listener instead of a full web
    framework so it can run on Windows 7 SP1 through Windows 11 with the
    inbox .NET Framework.  All state-changing payloads are authenticated and
    encrypted by Tool-Enterprise.ps1; this listener never writes a product
    key to a log or an unencrypted report.
#>
[CmdletBinding()]
param(
    [switch]$Stop
)

$ErrorActionPreference = "Stop"
$baseDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $baseDir "Tool-Runtime.ps1")
. (Join-Path $baseDir "Tool-ReportSchema.ps1")
. (Join-Path $baseDir "Tool-Enterprise.ps1")
. (Join-Path $baseDir "Tool-OfflinePolicy.ps1")
[void](Assert-ToolNativeArchitecture)
if (-not $Stop -and -not (Test-ToolEnterpriseNetworkActionAllowed)) {
    [Console]::Error.WriteLine((Get-ToolEnterpriseText "enterpriseHost.error.networkBlocked"))
    exit 30
}

function Write-ToolEnterpriseHostJsonResponse {
    param(
        [Parameter(Mandatory = $true)][Net.HttpListenerResponse]$Response,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [AllowNull()][object]$Value
    )
    $Response.StatusCode = $StatusCode
    $Response.ContentType = "application/json; charset=utf-8"
    $Response.ContentEncoding = [Text.Encoding]::UTF8
    $Response.KeepAlive = $false
    $json = if ($null -eq $Value) { "" } else { $Value | ConvertTo-Json -Depth 16 -Compress }
    $bytes = [Text.Encoding]::UTF8.GetBytes($json)
    $Response.ContentLength64 = $bytes.Length
    try {
        if ($bytes.Length -gt 0) { $Response.OutputStream.Write($bytes, 0, $bytes.Length) }
    } finally {
        try { $Response.OutputStream.Close() } catch {}
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Read-ToolEnterpriseHostRequestBody {
    param([Parameter(Mandatory = $true)][Net.HttpListenerRequest]$Request)
    if ($Request.ContentLength64 -lt 0 -or $Request.ContentLength64 -gt $script:ToolEnterpriseMaximumRequestBytes) {
        throw (Get-ToolEnterpriseText "enterpriseHost.error.requestTooLarge")
    }
    $length = [int]$Request.ContentLength64
    if ($length -eq 0) { return $null }
    $bytes = New-Object byte[] $length
    $offset = 0
    while ($offset -lt $length) {
        $read = $Request.InputStream.Read($bytes, $offset, $length - $offset)
        if ($read -le 0) { throw (Get-ToolEnterpriseText "enterpriseHost.error.requestIncomplete") }
        $offset += $read
    }
    try { return ([Text.Encoding]::UTF8.GetString($bytes) | ConvertFrom-Json) }
    finally { [Array]::Clear($bytes, 0, $bytes.Length) }
}

function Get-ToolEnterpriseHostClientId {
    param([Parameter(Mandatory = $true)][Net.HttpListenerRequest]$Request)
    $clientId = [string]$Request.Headers["X-Tool-ClientId"]
    $parsed = [Guid]::Empty
    if (-not [Guid]::TryParse($clientId, [ref]$parsed)) { throw (Get-ToolEnterpriseText "enterpriseHost.error.clientIdInvalid") }
    return $parsed.ToString("N")
}

function Test-ToolEnterpriseHostRemoteAddress {
    param(
        [Parameter(Mandatory = $true)][string]$Address,
        [Parameter(Mandatory = $true)][object]$Configuration
    )
    $parsed = $null
    if (-not [Net.IPAddress]::TryParse($Address, [ref]$parsed) -or $parsed.AddressFamily -ne [Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }
    if ($parsed.Equals([Net.IPAddress]::Loopback)) { return $true }
    $cidrs = @($Configuration.AllowedCidrs)
    if ($cidrs.Count -eq 0) { return $true }
    foreach ($cidr in $cidrs) {
        if (Test-ToolEnterpriseIpInCidr -Address $Address -Cidr ([string]$cidr)) { return $true }
    }
    return $false
}

function Get-ToolEnterpriseHostStatus {
    param([Parameter(Mandatory = $true)][object]$Configuration, [Parameter(Mandatory = $true)][datetime]$StartedAtUtc)
    # This endpoint is intentionally unauthenticated so clients can discover a
    # compatible listener before enrollment. Never expose server identity,
    # addresses, ACLs, uptime, or fleet information here.
    return [ordered]@{
        Accepted = $true
        ProtocolVersion = $script:ToolEnterpriseProtocolVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
    }
}

function Test-ToolEnterpriseHostReplay {
    param(
        [Parameter(Mandatory = $true)][hashtable]$ReplayCache,
        [Parameter(Mandatory = $true)][object]$OpenedEnvelope,
        [int]$MaximumEntries = 2048
    )
    $nonce = [string]$OpenedEnvelope.Nonce
    if ([string]::IsNullOrWhiteSpace($nonce)) { throw (Get-ToolEnterpriseText "enterpriseHost.error.envelopeNonceMissing") }
    $now = [DateTime]::UtcNow
    foreach ($key in @($ReplayCache.Keys)) {
        if (($now - [datetime]$ReplayCache[$key]).TotalMinutes -gt 15) { [void]$ReplayCache.Remove($key) }
    }
    if ($ReplayCache.ContainsKey($nonce)) { throw (Get-ToolEnterpriseText "enterpriseHost.error.envelopeReplay") }
    if ($ReplayCache.Count -ge $MaximumEntries) {
        $oldest = $ReplayCache.GetEnumerator() | Sort-Object Value | Select-Object -First 1
        if ($oldest) { [void]$ReplayCache.Remove([string]$oldest.Key) }
    }
    $ReplayCache[$nonce] = $now
}

function Write-ToolEnterpriseHostFailure {
    param([Parameter(Mandatory = $true)][object]$ErrorRecord)
    try {
        $paths = Get-ToolEnterprisePaths
        $safe = [ordered]@{
            SchemaVersion = $script:ToolEnterpriseSchemaVersion
            ToolVersion = $script:ToolEnterpriseToolVersion
            TimestampUtc = [DateTime]::UtcNow.ToString("o")
            Message = ConvertTo-ToolEnterpriseSafeText $ErrorRecord.Exception.Message 1200
        }
        Write-ToolEnterpriseJson -Path $paths.ServerError -Value $safe
        Write-ToolEnterpriseAudit -Scope Server -Event "Server.Error" -Message $safe.Message
    } catch {}
}

function Start-ToolEnterpriseHost {
    $paths = Initialize-ToolEnterpriseStorage
    $configuration = Get-ToolEnterpriseServerConfig
    if (-not $configuration -or [string]$configuration.Role -ne "Server") {
        throw (Get-ToolEnterpriseText "enterpriseHost.error.notConfigured")
    }
    if (Test-Path -LiteralPath $paths.ServerStop -PathType Leaf) {
        Remove-Item -LiteralPath $paths.ServerStop -Force -ErrorAction SilentlyContinue
    }

    $created = $false
    $mutex = New-Object Threading.Mutex($false, "Global\ThanhViet.ToolKiemTra.v4.6.EnterpriseServer", [ref]$created)
    if (-not $created) {
        $mutex.Dispose()
        throw (Get-ToolEnterpriseText "enterpriseHost.error.alreadyRunning")
    }

    $listener = New-Object Net.HttpListener
    $prefixAddress = if ([string]$configuration.BindAddress -eq "0.0.0.0") { "*" } else { [string]$configuration.BindAddress }
    $prefix = "http://$prefixAddress`:$([int]$configuration.Port)/tool/v1/"
    $startedAt = [DateTime]::UtcNow
    $replayCache = @{}
    $rateCache = @{}
    $lastHeartbeat = [DateTime]::MinValue
    $pendingAccept = $null
    $pidRecord = [ordered]@{
        SchemaVersion = $script:ToolEnterpriseSchemaVersion
        ToolVersion = $script:ToolEnterpriseToolVersion
        ProcessId = $PID
        Prefix = $prefix
        StartedAtUtc = $startedAt.ToString("o")
    }
    Write-ToolEnterpriseJson -Path $paths.ServerPid -Value $pidRecord

    try {
        $listener.Prefixes.Add($prefix)
        try { $listener.Start() }
        catch {
            throw (Get-ToolEnterpriseText "enterpriseHost.error.openPort" @($configuration.Port, $_.Exception.Message))
        }
        Write-ToolEnterpriseAudit -Scope Server -Event "Server.Started" -Message (Get-ToolEnterpriseText "enterpriseHost.audit.started") -Data ([ordered]@{
            ServerId=$configuration.ServerId; Prefix=$prefix; AllowedCidrs=@($configuration.AllowedCidrs)
        })

        while ($listener.IsListening) {
            if (Test-Path -LiteralPath $paths.ServerStop -PathType Leaf) { break }
            if (([DateTime]::UtcNow - $lastHeartbeat).TotalSeconds -ge 10) {
                $lastHeartbeat = [DateTime]::UtcNow
                Write-ToolEnterpriseJson -Path $paths.ServerHeartbeat -Value ([ordered]@{
                    SchemaVersion=$script:ToolEnterpriseSchemaVersion; ToolVersion=$script:ToolEnterpriseToolVersion
                    ProcessId=$PID; TimestampUtc=$lastHeartbeat.ToString("o"); ClientCount=@(Get-ToolEnterpriseServerClients).Count
                })
            }

            if (-not $pendingAccept) { $pendingAccept = $listener.BeginGetContext($null, $null) }
            if (-not $pendingAccept.AsyncWaitHandle.WaitOne(1000)) { continue }
            $context = $null
            try { $context = $listener.EndGetContext($pendingAccept) }
            catch { if ($listener.IsListening) { continue } }
            finally { $pendingAccept = $null }
            if (-not $context) { continue }

            $remoteAddress = ""
            try { $remoteAddress = [string]$context.Request.RemoteEndPoint.Address } catch {}
            $now = [DateTime]::UtcNow
            $rate = if ($rateCache.ContainsKey($remoteAddress)) { $rateCache[$remoteAddress] } else { [ordered]@{ Start=$now; Count=0 } }
            if (($now - [datetime]$rate.Start).TotalMinutes -ge 1) { $rate = [ordered]@{ Start=$now; Count=0 } }
            $rate.Count++
            $rateCache[$remoteAddress] = $rate
            if ($rate.Count -gt 120) {
                Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 429 -Value ([ordered]@{ Accepted=$false; Message=(Get-ToolEnterpriseText "enterpriseHost.response.rateLimited") })
                continue
            }

            try {
                if (-not (Test-ToolEnterpriseHostRemoteAddress -Address $remoteAddress -Configuration $configuration)) {
                    Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 403 -Value ([ordered]@{ Accepted=$false; Message=(Get-ToolEnterpriseText "enterpriseHost.response.addressDenied") })
                    continue
                }
                $path = $context.Request.Url.AbsolutePath.TrimEnd("/")
                $method = $context.Request.HttpMethod.ToUpperInvariant()
                $body = if ($method -eq "POST") { Read-ToolEnterpriseHostRequestBody -Request $context.Request } else { $null }
                $responseValue = $null

                if ($method -eq "GET" -and $path -eq "/tool/v1/status") {
                    $responseValue = Get-ToolEnterpriseHostStatus -Configuration $configuration -StartedAtUtc $startedAt
                    Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 200 -Value $responseValue
                    continue
                }

                if ($method -ne "POST" -or $path -notin @("/tool/v1/enroll", "/tool/v1/report", "/tool/v1/poll", "/tool/v1/result")) {
                    Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 404 -Value ([ordered]@{ Accepted=$false; Message=(Get-ToolEnterpriseText "enterpriseHost.response.endpointMissing") })
                    continue
                }
                if (-not $body) { throw (Get-ToolEnterpriseText "enterpriseHost.error.envelopeMissing") }

                if ($path -eq "/tool/v1/enroll") {
                    $pairingExpires = [DateTime]::Parse([string]$configuration.PairingExpiresAtUtc, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)
                    if ($pairingExpires.ToUniversalTime() -lt [DateTime]::UtcNow) { throw (Get-ToolEnterpriseText "enterpriseHost.error.pairingExpired") }
                    $pairingSecret = Get-ToolEnterpriseSecret -Path $paths.ServerPairingSecret
                    if (-not $pairingSecret) { throw (Get-ToolEnterpriseText "enterpriseHost.error.pairingSecretMissing") }
                    try {
                        $payloadId = [string]$body.Context
                        $opened = Open-ToolEnterpriseEnvelope -Secret $pairingSecret -ExpectedContext "enroll" -Envelope $body
                        Test-ToolEnterpriseHostReplay -ReplayCache $replayCache -OpenedEnvelope $opened
                        $payload = $opened.Payload
                        if ([string]$payload.ProtocolVersion -ne $script:ToolEnterpriseProtocolVersion -or
                            [string]$payload.ToolVersion -ne $script:ToolEnterpriseToolVersion) {
                            throw (Get-ToolEnterpriseText "enterpriseHost.error.clientVersionMismatch")
                        }
                        $clientId = [Guid]::Empty
                        if (-not [Guid]::TryParse([string]$payload.ClientId, [ref]$clientId)) { throw (Get-ToolEnterpriseText "enterpriseHost.error.enrollmentClientIdInvalid") }
                        $clientIdText = $clientId.ToString("N")
                        $clientSecret = New-ToolEnterpriseRandomBytes -Length 32
                        Set-ToolEnterpriseServerClientSecret -ClientId $clientIdText -Secret $clientSecret
                        $record = [pscustomobject][ordered]@{
                            SchemaVersion=$script:ToolEnterpriseSchemaVersion; ToolVersion=$script:ToolEnterpriseToolVersion
                            ClientId=$clientIdText; ComputerName=ConvertTo-ToolEnterpriseSafeText $payload.ComputerName 100
                            RemoteAddress=ConvertTo-ToolEnterpriseSafeText $remoteAddress 80
                            NetworkAddresses=@($payload.NetworkAddresses); LastSeenUtc=[DateTime]::UtcNow.ToString("o")
                            FirstSeenUtc=[DateTime]::UtcNow.ToString("o")
                            AllowRemoteLicenseChanges=[bool]$payload.AllowRemoteLicenseChanges
                            WindowsStatus="NotReported"; WindowsChannel=""; WindowsLast5=""
                            OfficeStatus="NotReported"; OfficeChannel=""; OfficeLast5=""
                            LatestReportPath=""
                        }
                        Write-ToolEnterpriseJson -Path (Get-ToolEnterpriseServerClientRecordPath -ClientId $clientIdText) -Value $record
                        $responsePayload = [ordered]@{
                            Accepted=$true; Message=(Get-ToolEnterpriseText "enterpriseHost.response.enrollmentSucceeded"); ServerId=[string]$configuration.ServerId
                            ClientId=$clientIdText; ClientSecret=(ConvertTo-ToolEnterpriseBase64Url -Bytes $clientSecret)
                        }
                        $response = New-ToolEnterpriseEnvelope -Secret $pairingSecret -Context "enroll-response:$clientIdText" -Payload $responsePayload
                        Write-ToolEnterpriseAudit -Scope Server -Event "Client.Enrolled" -Message (Get-ToolEnterpriseText "enterpriseHost.audit.clientEnrolled") -Data ([ordered]@{
                            ClientId=$clientIdText; ComputerName=$record.ComputerName; RemoteAddress=$remoteAddress
                        })
                        Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 200 -Value $response
                        [Array]::Clear($clientSecret, 0, $clientSecret.Length)
                    } finally { [Array]::Clear($pairingSecret, 0, $pairingSecret.Length) }
                    continue
                }

                $clientId = Get-ToolEnterpriseHostClientId -Request $context.Request
                $clientSecret = Get-ToolEnterpriseServerClientSecret -ClientId $clientId
                if (-not $clientSecret) { throw (Get-ToolEnterpriseText "enterpriseHost.error.clientNotEnrolled") }
                try {
                    if ($path -eq "/tool/v1/report") {
                        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "report:$clientId" -Envelope $body
                        Test-ToolEnterpriseHostReplay -ReplayCache $replayCache -OpenedEnvelope $opened
                        $report = $opened.Payload
                        $validation = Test-ToolReportEnvelope -Report $report -ExpectedReportKind "EnterpriseInventory" -ExpectedToolVersion $script:ToolEnterpriseToolVersion
                        if (-not $validation.Valid) { throw (Get-ToolEnterpriseText "enterpriseHost.error.reportInvalid" @(($validation.Errors -join '; '))) }
                        [void](Save-ToolEnterpriseServerReport -ClientId $clientId -Report $report -RemoteAddress $remoteAddress)
                        $responsePayload = [ordered]@{ Accepted=$true; Message=(Get-ToolEnterpriseText "enterpriseHost.response.reportReceived"); ReceivedAtUtc=[DateTime]::UtcNow.ToString("o") }
                        $response = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "report-response:$clientId" -Payload $responsePayload
                        Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 200 -Value $response
                    } elseif ($path -eq "/tool/v1/poll") {
                        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "poll:$clientId" -Envelope $body
                        Test-ToolEnterpriseHostReplay -ReplayCache $replayCache -OpenedEnvelope $opened
                        $pending = Get-ToolEnterprisePendingJobPackage -ClientId $clientId
                        $responsePayload = if ($pending) {
                            [ordered]@{ Accepted=$true; HasJob=$true; JobId=[string]$pending.JobId; JobEnvelope=$pending.Envelope }
                        } else {
                            [ordered]@{ Accepted=$true; HasJob=$false; JobId=""; JobEnvelope=$null }
                        }
                        $response = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "poll-response:$clientId" -Payload $responsePayload
                        Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 200 -Value $response
                    } else {
                        $opened = Open-ToolEnterpriseEnvelope -Secret $clientSecret -ExpectedContext "result:$clientId" -Envelope $body
                        Test-ToolEnterpriseHostReplay -ReplayCache $replayCache -OpenedEnvelope $opened
                        $result = $opened.Payload
                        [void](Save-ToolEnterpriseJobResult -ClientId $clientId -Result $result)
                        $responsePayload = [ordered]@{ Accepted=$true; Message=(Get-ToolEnterpriseText "enterpriseHost.response.jobResultReceived"); ReceivedAtUtc=[DateTime]::UtcNow.ToString("o") }
                        $response = New-ToolEnterpriseEnvelope -Secret $clientSecret -Context "result-response:$clientId" -Payload $responsePayload
                        Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 200 -Value $response
                    }
                } finally { [Array]::Clear($clientSecret, 0, $clientSecret.Length) }
            } catch {
                Write-ToolEnterpriseHostFailure -ErrorRecord $_
                try {
                    Write-ToolEnterpriseHostJsonResponse -Response $context.Response -StatusCode 400 -Value ([ordered]@{
                        Accepted=$false; Message=ConvertTo-ToolEnterpriseSafeText $_.Exception.Message 800
                    })
                } catch {}
            } finally {
                try { $context.Response.Close() } catch {}
            }
        }
    } finally {
        try { if ($listener.IsListening) { $listener.Stop() } } catch {}
        try { $listener.Close() } catch {}
        try { Remove-Item -LiteralPath $paths.ServerPid -Force -ErrorAction SilentlyContinue } catch {}
        try { Remove-Item -LiteralPath $paths.ServerHeartbeat -Force -ErrorAction SilentlyContinue } catch {}
        try { Remove-Item -LiteralPath $paths.ServerStop -Force -ErrorAction SilentlyContinue } catch {}
        try { Write-ToolEnterpriseAudit -Scope Server -Event "Server.Stopped" -Message (Get-ToolEnterpriseText "enterpriseHost.audit.stopped") } catch {}
        try { $mutex.ReleaseMutex() } catch {}
        $mutex.Dispose()
    }
}

try {
    $paths = Initialize-ToolEnterpriseStorage
    if ($Stop) {
        New-Item -ItemType File -Path $paths.ServerStop -Force | Out-Null
        exit 0
    }
    Start-ToolEnterpriseHost
    exit 0
} catch {
    try { Write-ToolEnterpriseHostFailure -ErrorRecord $_ } catch {}
    [Console]::Error.WriteLine([string]$_.Exception.Message)
    exit 1
}
