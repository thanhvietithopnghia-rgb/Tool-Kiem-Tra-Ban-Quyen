[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$errors = New-Object System.Collections.Generic.List[string]

function Add-AssistantVerificationError([string]$Message) {
    $script:errors.Add($Message)
}

foreach ($name in @('Tool-Assistant.ps1','tool-assistant-knowledge-v1.1.json','Tool-OfflinePolicy.ps1','Giao-Dien.ps1','Tool-Strings.vi-VN.json','Tool-Strings.en-US.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $name) -PathType Leaf)) {
        Add-AssistantVerificationError "Missing required assistant file: $name"
    }
}
if ($errors.Count -eq 0) {
    . (Join-Path $SourceDirectory 'Tool-Assistant.ps1')
    $knowledge = Get-ToolAssistantKnowledge
    if (-not (Test-ToolAssistantKnowledge -Knowledge $knowledge)) { Add-AssistantVerificationError 'Knowledge validation failed.' }
    $legacyKnowledge = ((Get-Content -LiteralPath (Join-Path $SourceDirectory 'tool-assistant-knowledge-v1.1.json') -Raw -Encoding UTF8) -replace '"KnowledgeVersion"\s*:\s*"1\.1\.0"', '"KnowledgeVersion": "1.0.0"') | ConvertFrom-Json
    if (Test-ToolAssistantKnowledge -Knowledge $legacyKnowledge) { Add-AssistantVerificationError 'An obsolete cached knowledge file was not rejected.' }
    if (@($knowledge.Entries).Count -lt 20) { Add-AssistantVerificationError 'Knowledge coverage is below 20 entries.' }
    $metadata = Get-ToolAssistantMetadata
    if ([bool]$metadata.PaidApiRequired) { Add-AssistantVerificationError 'Assistant must not require a paid API.' }
    if ([bool]$metadata.CodexRequired) { Add-AssistantVerificationError 'Assistant must not depend on Codex.' }
    if ([bool]$metadata.ReportUpload) { Add-AssistantVerificationError 'Assistant must not upload reports.' }
    if ([bool]$metadata.AutomaticRemediation) { Add-AssistantVerificationError 'Assistant must not remediate automatically.' }
    if (-not [bool]$metadata.PortableEveryMachine -or [bool]$metadata.CentralServerRequired) {
        Add-AssistantVerificationError 'Assistant must run independently on every device without a central server.'
    }
    if ([string]$metadata.KnowledgeStorage -ne 'BundledAndPerUserLocalCache' -or
        [string]$metadata.ReportContextSource -ne 'CurrentDeviceLocalReportOnly') {
        Add-AssistantVerificationError 'Assistant local knowledge/report scope metadata is invalid.'
    }

    $keywordOwners = @{}
    $keywordCount = 0
    foreach ($entry in @($knowledge.Entries)) {
        foreach ($keywordValue in @($entry.Keywords)) {
            $keyword = ConvertTo-ToolAssistantSearchKey -Value ([string]$keywordValue)
            $keywordCount++
            if ($keywordOwners.ContainsKey($keyword)) {
                Add-AssistantVerificationError "Duplicate normalized keyword '$keyword' in '$($keywordOwners[$keyword])' and '$($entry.Id)'."
                continue
            }
            $keywordOwners[$keyword] = [string]$entry.Id
            $resolvedKeyword = Resolve-ToolAssistantEntry -QueryKey $keyword -Knowledge $knowledge
            if ($null -eq $resolvedKeyword.Entry -or [string]$resolvedKeyword.Entry.Id -ne [string]$entry.Id) {
                Add-AssistantVerificationError "Cross-routed keyword '$keyword': expected '$($entry.Id)'."
            }
        }
    }
    if ($keywordCount -lt 270) { Add-AssistantVerificationError "Knowledge keyword coverage is below 270: actual $keywordCount." }

    $routeTests = @(
        @{ Question='đọc báo cáo'; Entry='report-evidence' },
        @{ Question='báo cáo lưu ở đâu'; Entry='report-center' },
        @{ Question='chưa đủ bằng chứng'; Entry='manual-review' },
        @{ Question='mã lỗi 0xC004D302'; Entry='unverifiable' },
        @{ Question='cách dùng chức năng số 8'; Entry='enterprise' }
        @{ Question='báo cáo có khẳng định đk k'; Entry='report-legal-limit' }
        @{ Question='pdf bị khuyết dòng và cắt chữ'; Entry='report-pdf' }
        @{ Question='ẩn pm hệ thống trong pdf'; Entry='software-system-filter' }
        @{ Question='tự tìm máy chủ khi ô ip trống'; Entry='enterprise-discovery' }
        @{ Question='hash mismatch có phải bản quyền lậu không'; Entry='integrity-compromised' }
    )
    foreach ($test in $routeTests) {
        $queryKey = ConvertTo-ToolAssistantSearchKey -Value $test.Question
        $route = Resolve-ToolAssistantEntry -QueryKey $queryKey -Knowledge $knowledge
        if ($null -eq $route.Entry -or [string]$route.Entry.Id -ne [string]$test.Entry) {
            Add-AssistantVerificationError "Specific intent '$($test.Question)' routed to '$([string]$route.Entry.Id)' instead of '$($test.Entry)'."
        }
    }

    $answerTests = @(
        @{ Question='khong the xac minh ban quyen la gi'; Expected='CHƯA XÁC ĐỊNH' },
        @{ Question='che do ofline hoat dong sao'; Expected='Offline' },
        @{ Question='tool co can api codex khong'; Expected='tri thức cục bộ' },
        @{ Question='bao cao luu o dau'; Expected='BaoCao-Tool-Kiem-Tra' },
        @{ Question='doc bao cao'; Expected='ba lớp' },
        @{ Question='chua du bang chung'; Expected='kiểm tra thủ công' },
        @{ Question='cach dung chuc nang so 8'; Expected='Doanh nghiệp' },
        @{ Question='tool co sua crack tu dong khong'; Expected='người dùng chủ động' },
        @{ Question='cach nau bun bo hue'; Expected='ngoài phạm vi' }
        @{ Question='báo cáo có khẳng định đk k'; Expected='hóa đơn' }
        @{ Question='mỗi lần quét có tạo thư mục riêng k'; Expected='không tạo thư mục con' }
        @{ Question='pm hệ thống trong pdf quá dài'; Expected='phụ lục' }
        @{ Question='cách luna cập nhật'; Expected='thêm' }
    )
    foreach ($test in $answerTests) {
        $answer = Get-ToolAssistantAnswer -Question $test.Question -Culture 'vi-VN' -Knowledge $knowledge
        if ($answer -notlike ('*' + $test.Expected + '*')) {
            Add-AssistantVerificationError "Unexpected answer for '$($test.Question)'."
        }
    }

    if (-not [string]::IsNullOrEmpty((Resolve-ToolAssistantReportJsonPath -Path '\\server\share\report.json'))) {
        Add-AssistantVerificationError 'Assistant accepted a network/UNC report path.'
    }
    $reportFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('tool-assistant-report-' + [Guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $reportFixtureRoot | Out-Null
        $invalidReportPath = Join-Path $reportFixtureRoot 'unrelated.json'
        [IO.File]::WriteAllText($invalidReportPath, '{"Name":"not-a-tool-report"}', (New-Object Text.UTF8Encoding($false)))
        if ($null -ne (Get-ToolAssistantReportContext -ReportPath $invalidReportPath)) {
            Add-AssistantVerificationError 'Assistant accepted JSON that was not generated as a Tool report.'
        }
        $validReportPath = Join-Path $reportFixtureRoot 'report.json'
        $validReportJson = '{"SchemaVersion":"1.5","ReportKind":"InventoryAndLicense","CreatedAt":"2026-08-08T00:00:00Z","Mode":"Windows","OfflineMode":true,"WindowsStatus":"Unknown","WindowsChannel":"Unknown","WindowsConclusionCode":"Undetermined","WindowsConclusion":"Test Windows","OfficeDetected":false,"OfficeStatus":"NotDetected","OfficeConclusionCode":"NotDetected","OfficeConclusion":"Test Office","SuspiciousFindingCount":1,"ManualReviewFindingCount":2,"ThirdPartyApplicationCount":3,"ThirdPartyHighSeverityCount":0}'
        [IO.File]::WriteAllText($validReportPath, $validReportJson, (New-Object Text.UTF8Encoding($false)))
        $validReportContext = Get-ToolAssistantReportContext -ReportPath $validReportPath
        if ($null -eq $validReportContext -or [string]$validReportContext.WindowsConclusion -ne 'Test Windows') {
            Add-AssistantVerificationError 'Assistant could not read a valid local Tool report fixture.'
        }
        $englishReportAnswer = Format-ToolAssistantReportContext -Context $validReportContext -Culture 'en-US'
        $vietnameseReportAnswer = Format-ToolAssistantReportContext -Context $validReportContext -Culture 'vi-VN'
        if ($englishReportAnswer -notmatch 'Windows:\s+Undetermined' -or $englishReportAnswer -match 'Chưa|Không phát hiện|Test Windows') {
            Add-AssistantVerificationError 'English report context contains an unsynchronized conclusion.'
        }
        if ($vietnameseReportAnswer -notmatch 'Windows:\s+Chưa xác định' -or $vietnameseReportAnswer -match 'No conclusion|Not scanned') {
            Add-AssistantVerificationError 'Vietnamese report context contains an unsynchronized conclusion.'
        }
    } finally {
        if (Test-Path -LiteralPath $reportFixtureRoot -PathType Container) { Remove-Item -LiteralPath $reportFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue }
    }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $testInput = New-Object Windows.Forms.TextBox
    $testInputFrame = New-Object Windows.Forms.Panel
    $testSend = New-Object Windows.Forms.Button
    $testChat = New-Object Windows.Forms.FlowLayoutPanel
    $testHost = New-Object Windows.Forms.Form
    $testLayout = New-Object Windows.Forms.TableLayoutPanel
    $testComposer = New-Object Windows.Forms.Panel
    $testHost.ShowInTaskbar = $false
    $testHost.StartPosition = 'Manual'
    $testHost.Location = New-Object Drawing.Point(-32000, -32000)
    $testHost.Size = New-Object Drawing.Size(720, 270)
    $testLayout.Dock = 'Fill'
    $testLayout.ColumnCount = 1
    $testLayout.RowCount = 2
    [void]$testLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100)))
    [void]$testLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100)))
    [void]$testLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 64)))
    $testHost.Controls.Add($testLayout)
    $testChat.Dock = 'Fill'
    $testChat.FlowDirection = [Windows.Forms.FlowDirection]::TopDown
    $testChat.WrapContents = $false
    $testChat.AutoScroll = $true
    $testChat.Padding = New-Object Windows.Forms.Padding(12)
    $testComposer.Dock = 'Fill'
    $testComposer.BackColor = [Drawing.Color]::WhiteSmoke
    $testLayout.Controls.Add($testChat, 0, 0)
    $testLayout.Controls.Add($testComposer, 0, 1)
    $testHost.Show()
    [Windows.Forms.Application]::DoEvents()
    $testSpeakerFont = New-Object Drawing.Font('Segoe UI', 9, [Drawing.FontStyle]::Bold)
    $testMessageFont = New-Object Drawing.Font('Segoe UI', 10)
    $testRenderTimer = New-Object Windows.Forms.Timer
    $testRenderTimer.Interval = 15
    try {
        $testState = [pscustomobject]@{
            Input=$testInput; Chat=$testChat; SendButton=$testSend; Culture='vi-VN'; Knowledge=$knowledge; ReportContext=$null
            SpeakerFont=$testSpeakerFont; MessageFont=$testMessageFont; Transcript=(New-Object Text.StringBuilder); IsSubmitting=$false
            PendingRevealControl=$null; RevealQueued=$false; RenderTimer=$testRenderTimer
            UserBubbleColor=[Drawing.Color]::FromArgb(0,98,218); UserTextColor=[Drawing.Color]::White
            UserBubbleBorderColor=[Drawing.Color]::FromArgb(0,72,164)
            AssistantBubbleColor=[Drawing.Color]::FromArgb(232,241,252); AssistantTextColor=[Drawing.Color]::Black
            AssistantBubbleBorderColor=[Drawing.Color]::FromArgb(143,174,211); AssistantHeaderColor=[Drawing.Color]::FromArgb(0,98,218)
            InputFrame=$testInputFrame; InputIdleBorderColor=[Drawing.Color]::FromArgb(118,136,162)
            InputFocusBorderColor=[Drawing.Color]::FromArgb(0,98,218)
        }
        $testRenderTimer.Tag = $testState
        $testRenderTimer.Add_Tick({
            param($sender, $eventArgs)
            $sender.Stop()
            $state = $sender.Tag
            $latest = $state.PendingRevealControl
            $state.PendingRevealControl = $null
            Complete-ToolAssistantConversationLayout -State $state -LatestControl $latest
        })
        $testInput.Text = 'kms là gì'
        $submittedAnswer = Invoke-ToolAssistantQuestion -State $testState
        if ([string]::IsNullOrWhiteSpace([string]$submittedAnswer) -or
            $testChat.Controls.Count -ne 2 -or
            [string]$testChat.Controls[0].Tag.Role -ne 'User' -or
            [string]$testChat.Controls[1].Tag.Role -ne 'Assistant' -or
            $testChat.Controls[0].Tag.Bubble.Left -le $testChat.Controls[1].Tag.Bubble.Left -or
            $testChat.Controls[0].Tag.Bubble.BackColor.ToArgb() -eq $testChat.Controls[1].Tag.Bubble.BackColor.ToArgb() -or
            $testChat.Controls[0].Tag.Bubble.Tag.ToArgb() -eq $testChat.Controls[1].Tag.Bubble.Tag.ToArgb() -or
            $testState.Transcript.ToString() -notmatch 'Bạn\s+kms là gì\s+Trợ lý Tool') {
            Add-AssistantVerificationError 'The shared Send/Enter submission path did not append a question and answer.'
        }
        Set-ToolAssistantInputFrameState -State $testState -Focused $false
        $idleInputBorder = $testInputFrame.BackColor.ToArgb()
        Set-ToolAssistantInputFrameState -State $testState -Focused $true
        if ($idleInputBorder -eq $testInputFrame.BackColor.ToArgb() -or
            $testInputFrame.BackColor.ToArgb() -ne $testState.InputFocusBorderColor.ToArgb()) {
            Add-AssistantVerificationError 'The chat input frame does not expose a distinct focus border.'
        }

        $testHeader = New-Object Windows.Forms.Panel
        $testHeader.Size = New-Object Drawing.Size(660, 72)
        $testHeaderTitle = New-Object Windows.Forms.Label
        $testHeaderTitle.Location = New-Object Drawing.Point(18, 10)
        $testHeaderScope = New-Object Windows.Forms.Label
        $testHeaderScope.Location = New-Object Drawing.Point(20, 43)
        $testHeaderMode = New-Object Windows.Forms.Label
        Set-ToolAssistantHeaderBounds -Header $testHeader -TitleLabel $testHeaderTitle -ScopeLabel $testHeaderScope -ModeLabel $testHeaderMode
        if ($testHeaderMode.Right -gt ($testHeader.ClientSize.Width - 16) -or
            $testHeaderMode.Left -le $testHeaderScope.Right -or $testHeaderMode.Width -lt 220) {
            Add-AssistantVerificationError 'The Offline/local-knowledge badge is clipped or crowds the header text.'
        }
        $testHeaderMode.Dispose(); $testHeaderScope.Dispose(); $testHeaderTitle.Dispose(); $testHeader.Dispose()
        $controlCountBeforeDuplicate = $testChat.Controls.Count
        $testInput.Text = 'office là gì'
        $testState.IsSubmitting = $true
        $duplicateAnswer = Invoke-ToolAssistantQuestion -State $testState
        if (-not [string]::IsNullOrEmpty([string]$duplicateAnswer) -or
            $testChat.Controls.Count -ne $controlCountBeforeDuplicate -or
            $testInput.Text -ne 'office là gì') {
            Add-AssistantVerificationError 'Duplicate submission was not blocked while an answer was being processed.'
        }
        $testState.IsSubmitting = $false

        Clear-ToolAssistantConversation -State $testState
        foreach ($index in 1..8) {
            [void](Add-ToolAssistantChatMessage -State $testState -Role Assistant -Message ("Dòng kiểm thử hiển thị $index. Nội dung đủ dài để tạo vùng cuộn trong hội thoại."))
        }
        $testInput.Text = 'office là gì'
        $immediateAnswer = Invoke-ToolAssistantQuestion -State $testState
        for ($pump = 0; $pump -lt 5 -and $testRenderTimer.Enabled; $pump++) {
            [Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 20
        }
        $answerControl = $testChat.Controls[$testChat.Controls.Count - 1]
        $chatScreen = $testChat.RectangleToScreen($testChat.ClientRectangle)
        $answerScreen = $answerControl.RectangleToScreen($answerControl.ClientRectangle)
        $composerScreen = $testComposer.RectangleToScreen($testComposer.ClientRectangle)
        $visibleAnswer = [Drawing.Rectangle]::Intersect($chatScreen, $answerScreen)
        $answerMetadata = $answerControl.Tag
        $answerIsComplete = [bool](
            $visibleAnswer.Width -eq $answerScreen.Width -and
            $visibleAnswer.Height -eq $answerScreen.Height -and
            $answerMetadata.MessageLabel.Bottom -le $answerMetadata.Bubble.ClientSize.Height
        )
        if ([string]::IsNullOrWhiteSpace([string]$immediateAnswer) -or $visibleAnswer.Width -le 0 -or $visibleAnswer.Height -le 0 -or
            -not $answerIsComplete -or $chatScreen.Bottom -gt $composerScreen.Top -or
            $testRenderTimer.Enabled -or [bool]$testState.RevealQueued -or $null -ne $testState.PendingRevealControl) {
            Add-AssistantVerificationError ("The complete answer was not laid out above the composer, scrolled into view, and painted during the same submission. chat={0}; answer={1}; visible={2}; composer={3}; labelBottom={4}; bubbleHeight={5}; timer={6}; queued={7}; pending={8}" -f $chatScreen,$answerScreen,$visibleAnswer,$composerScreen,$answerMetadata.MessageLabel.Bottom,$answerMetadata.Bubble.ClientSize.Height,$testRenderTimer.Enabled,$testState.RevealQueued,($null -ne $testState.PendingRevealControl))
        }

        Clear-ToolAssistantConversation -State $testState
        if ($testChat.Controls.Count -ne 0 -or $testState.Transcript.Length -ne 0) {
            Add-AssistantVerificationError 'Clearing the bubble conversation did not clear both UI and transcript.'
        }
    } finally {
        $testRenderTimer.Stop(); $testRenderTimer.Dispose(); $testHost.Close(); $testHost.Dispose(); $testInput.Dispose(); $testInputFrame.Dispose(); $testSend.Dispose(); $testChat.Dispose(); $testComposer.Dispose(); $testLayout.Dispose(); $testSpeakerFont.Dispose(); $testMessageFont.Dispose()
    }

    $oldOfflineMode = [string]$env:TOOL_OFFLINE_MODE
    $oldSettingsPath = [string]$env:TOOL_OFFLINE_SETTINGS_PATH
    $temporarySettings = Join-Path ([IO.Path]::GetTempPath()) ('tool-offline-verifier-' + [Guid]::NewGuid().ToString('N') + '.json')
    try {
        [IO.File]::WriteAllText($temporarySettings, '{"OfflineMode":false}', (New-Object Text.UTF8Encoding($false)))
        Remove-Item Env:TOOL_OFFLINE_MODE -ErrorAction SilentlyContinue
        $env:TOOL_OFFLINE_SETTINGS_PATH = $temporarySettings
        . (Join-Path $SourceDirectory 'Tool-OfflinePolicy.ps1')
        if (-not (Get-ToolOfflineMode)) { Add-AssistantVerificationError 'Fresh process did not fail closed to Offline.' }
    } finally {
        if ($oldOfflineMode) { $env:TOOL_OFFLINE_MODE = $oldOfflineMode } else { Remove-Item Env:TOOL_OFFLINE_MODE -ErrorAction SilentlyContinue }
        if ($oldSettingsPath) { $env:TOOL_OFFLINE_SETTINGS_PATH = $oldSettingsPath } else { Remove-Item Env:TOOL_OFFLINE_SETTINGS_PATH -ErrorAction SilentlyContinue }
        Remove-Item -LiteralPath $temporarySettings -Force -ErrorAction SilentlyContinue
    }

    $guiSource = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Giao-Dien.ps1') -Raw -Encoding UTF8
    foreach ($requiredToken in @('$introAssistantButton','Show-ToolAssistantWindow','TitleLabel','DescriptionLabel','TitleColor')) {
        if (-not $guiSource.Contains($requiredToken)) { Add-AssistantVerificationError "Dashboard integration token missing: $requiredToken" }
    }
    if ($guiSource -notmatch 'RequestOnline\s+\$requestAssistantOnline') {
        Add-AssistantVerificationError 'Dashboard does not pass the current-session Online callback to Tool Assistant.'
    }
    $assistantSource = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-Assistant.ps1') -Raw -Encoding UTF8
    foreach ($requiredToken in @('$send.Tag = $assistantState','Queue-ToolAssistantQuestion -State $sender.Tag','$eventArgs.Handled = $true','BeginInvoke','SubmissionQueued','ConnectOnline','ConnectOnlineTip','Update-ToolAssistantConnectionUi','Update-ToolAssistantConversationUi','Complete-ToolAssistantConversationLayout','Set-ToolAssistantHeaderBounds','Set-ToolAssistantInputFrameState','InputIdleBorderColor','UserBubbleBorderColor','AssistantBubbleBorderColor','RenderTimer','PendingRevealControl','RevealQueued','[Windows.Forms.Application]::DoEvents()','Windows.Forms.FlowLayoutPanel','Windows.Forms.TableLayoutPanel','Role User','Role Assistant','IsSubmitting','SendButton.Enabled')) {
        if (-not $assistantSource.Contains($requiredToken)) { Add-AssistantVerificationError "Assistant UI interaction token missing: $requiredToken" }
    }
    if ($assistantSource.Contains('New-Object Windows.Forms.RichTextBox')) {
        Add-AssistantVerificationError 'Assistant conversation still uses a shared RichTextBox instead of separate bubbles.'
    }
    if ($assistantSource -match '"Scope"[^\r\n]+(?:paid API|API trả phí|Codex)') {
        Add-AssistantVerificationError 'Assistant scope line still contains API/Codex promotional text.'
    }
    $knowledgePublishedText = [string]::Join("`n", @($knowledge.Entries | ForEach-Object {
        [string]$_.TitleVi; [string]$_.TitleEn; [string]$_.AnswerVi; [string]$_.AnswerEn
    }))
    if ($knowledgePublishedText -match '(?i)API trả phí|paid API|Codex') {
        Add-AssistantVerificationError 'Published assistant knowledge still contains the removed API/Codex sentence.'
    }
    foreach ($neutralityPattern in @('(?i)(?<![\p{L}\p{N}])luna(?![\p{L}\p{N}])','(?i)(?<![\p{L}\p{N}])caca(?![\p{L}\p{N}])')) {
        if ($assistantSource -match $neutralityPattern -or $knowledgePublishedText -match $neutralityPattern) {
            Add-AssistantVerificationError "Published assistant contains a personal form of address matching '$neutralityPattern'."
        }
    }
    $vi = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-Strings.vi-VN.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $en = Get-Content -LiteralPath (Join-Path $SourceDirectory 'Tool-Strings.en-US.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([string]$vi.'about.technology.body' -match '(?i)API trả phí|Codex' -or [string]$en.'about.technology.body' -match '(?i)paid API|Codex') {
        Add-AssistantVerificationError 'Product information still contains the removed API/Codex sentence.'
    }
    $englishOfflineSync = Sync-ToolAssistantKnowledge -OnlineMode $false -Culture 'en-US'
    if ([string]$englishOfflineSync.Message -notmatch '^Tool Assistant is Offline' -or [string]$englishOfflineSync.Message -match 'Trợ lý|tri thức') {
        Add-AssistantVerificationError 'Assistant synchronization status is not fully localized in English.'
    }
    if ([string]$vi.'report.license.windows.unverifiableShort' -notlike 'CHƯA XÁC ĐỊNH*') {
        Add-AssistantVerificationError 'Short Windows conclusion is not CHUA XAC DINH.'
    }
    if ([string]$vi.'report.license.windows.unverifiable' -notlike '*không chứng minh giấy phép hợp lệ hoặc không hợp lệ*') {
        Add-AssistantVerificationError 'Detailed Windows conclusion is not evidence-neutral.'
    }
}

if ($errors.Count -gt 0) {
    Write-Host "VERIFY-ASSISTANT: $($errors.Count) error(s)." -ForegroundColor Red
    $errors | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
}
Write-Host 'VERIFY-ASSISTANT: 0 errors (270+ keywords + natural routing + immediate bubbles + duplicate lock + Send/Enter + Online control).' -ForegroundColor Green
exit 0
