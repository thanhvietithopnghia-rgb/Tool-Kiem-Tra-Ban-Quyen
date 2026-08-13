[CmdletBinding()]
param([string]$SourceDirectory = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($SourceDirectory)) { $SourceDirectory = $PSScriptRoot }
$errors = New-Object System.Collections.Generic.List[string]

function Add-AssistantVerificationError([string]$Message) {
    $script:errors.Add($Message)
}

foreach ($name in @('Tool-Assistant.ps1','tool-assistant-knowledge-v1.1.json','tool-assistant-knowledge-v1.1.json.p7s','SIGN-ASSISTANT-KNOWLEDGE.ps1','Tool-OfflinePolicy.ps1','Giao-Dien.ps1','Tool-Strings.vi-VN.json','Tool-Strings.en-US.json')) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $name) -PathType Leaf)) {
        Add-AssistantVerificationError "Missing required assistant file: $name"
    }
}
if ($errors.Count -eq 0) {
    . (Join-Path $SourceDirectory 'Tool-Assistant.ps1')
    $knowledge = Get-ToolAssistantKnowledge
    if (-not (Test-ToolAssistantKnowledge -Knowledge $knowledge)) { Add-AssistantVerificationError 'Knowledge validation failed.' }
    $knowledgePath = Join-Path $SourceDirectory 'tool-assistant-knowledge-v1.1.json'
    $signaturePath = Join-Path $SourceDirectory 'tool-assistant-knowledge-v1.1.json.p7s'
    $knowledgeBytes = [IO.File]::ReadAllBytes($knowledgePath)
    $signatureBytes = [IO.File]::ReadAllBytes($signaturePath)
    if (-not (Test-ToolAssistantKnowledgeSignature -ContentBytes $knowledgeBytes -SignatureBytes $signatureBytes)) {
        Add-AssistantVerificationError 'Bundled knowledge detached signature validation failed.'
    }
    if (-not (Read-ToolAssistantKnowledgeFile -Path $knowledgePath -SignaturePath $signaturePath -RequireSignature)) {
        Add-AssistantVerificationError 'Signed knowledge reader rejected the published package.'
    }
    $tamperedBytes = New-Object byte[] $knowledgeBytes.Length
    [Array]::Copy($knowledgeBytes, $tamperedBytes, $knowledgeBytes.Length)
    $tamperedBytes[[Math]::Max(0, $tamperedBytes.Length - 2)] = $tamperedBytes[[Math]::Max(0, $tamperedBytes.Length - 2)] -bxor 1
    if (Test-ToolAssistantKnowledgeSignature -ContentBytes $tamperedBytes -SignatureBytes $signatureBytes) {
        Add-AssistantVerificationError 'Detached signature accepted tampered knowledge bytes.'
    }
    $legacyKnowledge = ((Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8) -replace '"KnowledgeVersion"\s*:\s*"1\.3\.0"', '"KnowledgeVersion": "1.2.0"') | ConvertFrom-Json
    if (Test-ToolAssistantKnowledge -Knowledge $legacyKnowledge) { Add-AssistantVerificationError 'An obsolete cached knowledge file was not rejected.' }
    $compatibleFutureKnowledge = (Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8) | ConvertFrom-Json
    $compatibleFutureKnowledge.KnowledgeVersion = '1.3.1'
    $compatibleFutureKnowledge.UpdatedAtUtc = '2026-08-13T05:16:00Z'
    $compatibleFutureKnowledge.ReleasedWithToolVersion = '4.8.0.1'
    if (-not (Test-ToolAssistantKnowledge -Knowledge $compatibleFutureKnowledge)) {
        Add-AssistantVerificationError 'A newer signed-compatible knowledge version cannot evolve independently of the EXE.'
    }
    if (@($knowledge.Entries).Count -lt 20) { Add-AssistantVerificationError 'Knowledge coverage is below 20 entries.' }
    $metadata = Get-ToolAssistantMetadata
    if ([bool]$metadata.PaidApiRequired) { Add-AssistantVerificationError 'Assistant must not require a paid API.' }
    if ([bool]$metadata.CodexRequired) { Add-AssistantVerificationError 'Assistant must not depend on Codex.' }
    if ([bool]$metadata.ReportUpload) { Add-AssistantVerificationError 'Assistant must not upload reports.' }
    if ([bool]$metadata.AutomaticRemediation) { Add-AssistantVerificationError 'Assistant must not remediate automatically.' }
    if (-not [bool]$metadata.PortableEveryMachine -or [bool]$metadata.CentralServerRequired) {
        Add-AssistantVerificationError 'Assistant must run independently on every device without a central server.'
    }
    if ([string]$metadata.KnowledgeStorage -ne 'BundledAndSignedPerUserLocalCache' -or
        [string]$metadata.ReportContextSource -ne 'CurrentDeviceLocalReportOnly') {
        Add-AssistantVerificationError 'Assistant local knowledge/report scope metadata is invalid.'
    }
    if ([string]$metadata.OnlineTransfer -ne 'DownloadOnlySignedKnowledgePackage' -or
        [string]$metadata.KnowledgeUpdateVerification -ne 'DetachedCmsSha256PinnedCertificate' -or
        -not [bool]$metadata.KnowledgeRollbackProtection -or [bool]$metadata.QuestionUpload -or
        [bool]$metadata.UnboundedSelfTraining -or [bool]$metadata.ExternalTopicLearning) {
        Add-AssistantVerificationError 'Signed knowledge, privacy, rollback, or bounded-learning metadata is invalid.'
    }
    if ([string]$metadata.CoverageMode -ne 'KnowledgePlusBundledDocumentation' -or
        -not [bool]$metadata.ContextAwareFollowUp -or -not [bool]$metadata.ContextualOutOfScope) {
        Add-AssistantVerificationError 'Assistant broad coverage, follow-up context, or contextual boundary metadata is invalid.'
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
    if ($keywordCount -lt 390) { Add-AssistantVerificationError "Knowledge keyword coverage is below 390: actual $keywordCount." }

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
        @{ Question='phiên bản hiện tại của tool'; Entry='tool-version' }
        @{ Question='tool do ai phát triển'; Entry='tool-author' }
        @{ Question='tóm tắt nội dung chính của tool'; Entry='tool-overview' }
        @{ Question='nguyên tắc hoạt động của công cụ'; Entry='tool-principles' }
        @{ Question='liệt kê tất cả chức năng'; Entry='feature-overview' }
        @{ Question='cách dùng chức năng số 7'; Entry='oem' }
        @{ Question='cách sao lưu trước khi sửa'; Entry='backup-restore' }
        @{ Question='không thấy phần mềm cần kiểm tra'; Entry='software-not-found' }
        @{ Question='pdf không tạo được'; Entry='report-pdf-failure' }
        @{ Question='cách xóa cấu hình máy chủ'; Entry='enterprise-server-management' }
        @{ Question='cách ghép nối máy trạm'; Entry='enterprise-client-management' }
        @{ Question='tool không mở được file exe'; Entry='launch-troubleshooting' }
        @{ Question='online không đồng bộ được'; Entry='online-troubleshooting' }
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
        @{ Question='cách luna cập nhật'; Expected='manifest' }
        @{ Question='phiên bản hiện tại của tool'; Expected='v4.8.0.0' }
        @{ Question='do ai phát triển'; Expected='Thanh Việt' }
        @{ Question='tóm tắt nội dung chính'; Expected='một-EXE' }
        @{ Question='nguyên tắc của tool'; Expected='Offline' }
        @{ Question='tool có những chức năng nào'; Expected='10 chức năng' }
        @{ Question='hdsd chức năng 1'; Expected='chọn mức riêng tư' }
        @{ Question='cách dùng chức năng 7'; Expected='Khôi phục key OEM' }
        @{ Question='cách sao lưu'; Expected='không phải chức năng số 7' }
        @{ Question='không thấy phần mềm cần kiểm tra'; Expected='quyền Administrator' }
        @{ Question='pdf không tạo được'; Expected='dùng HTML' }
        @{ Question='cách xóa cấu hình máy chủ'; Expected='giữ báo cáo' }
        @{ Question='cách ghép nối máy trạm'; Expected='mã ghép nối' }
        @{ Question='tool không mở được file exe'; Expected='không chạy trong ZIP' }
        @{ Question='online không đồng bộ được'; Expected='DNS' }
        @{ Question='yêu cầu hệ thống của tool'; Expected='Windows 7 SP1' }
        @{ Question='tool viết bằng gì'; Expected='C#' }
        @{ Question='cách chuyển giao diện tối'; Expected='Sáng/Tối' }
    )
    foreach ($test in $answerTests) {
        $answer = Get-ToolAssistantAnswer -Question $test.Question -Culture 'vi-VN' -Knowledge $knowledge
        if ($answer -notlike ('*' + $test.Expected + '*')) {
            Add-AssistantVerificationError "Unexpected answer for '$($test.Question)'."
        }
    }

    $windowsFollowUp = Get-ToolAssistantAnswer -Question 'cách dùng nó' -PreviousQuestion 'chức năng 3 là gì' -Culture 'vi-VN' -Knowledge $knowledge
    $oemFollowUp = Get-ToolAssistantAnswer -Question 'thế còn chức năng 7' -PreviousQuestion 'cách dùng chức năng 6' -Culture 'vi-VN' -Knowledge $knowledge
    if ($windowsFollowUp -notmatch 'Chức năng 3.*Bản quyền Windows|Chức năng 3.*trạng thái kích hoạt') {
        Add-AssistantVerificationError 'Context follow-up did not retain the Windows feature topic.'
    }
    if ($oemFollowUp -notmatch 'Chức năng 7.*OEM' -or $oemFollowUp -match 'không phải chức năng số 7') {
        Add-AssistantVerificationError 'Context follow-up cross-routed feature 7 away from OEM recovery.'
    }

    $offlineNow = Get-ToolAssistantAnswer -Question 'tool đang online hay offline hiện tại' -Culture 'vi-VN' -Knowledge $knowledge -OnlineMode $false
    $onlineNow = Get-ToolAssistantAnswer -Question 'trạng thái online của tool lúc này' -Culture 'vi-VN' -Knowledge $knowledge -OnlineMode $true
    if ($offlineNow -notmatch 'hiện đang Offline' -or $onlineNow -notmatch 'đang Online trong phiên hiện tại') {
        Add-AssistantVerificationError 'Assistant did not use the actual current Online/Offline state.'
    }

    $cookingOutside = Get-ToolAssistantAnswer -Question 'cách nấu bún bò huế' -Culture 'vi-VN' -Knowledge $knowledge
    $weatherOutside = Get-ToolAssistantAnswer -Question 'thời tiết hôm nay' -Culture 'vi-VN' -Knowledge $knowledge
    $relatedUnknown = Get-ToolAssistantAnswer -Question 'tool quản lý một định dạng nội bộ chưa được tài liệu hóa thế nào' -Culture 'vi-VN' -Knowledge $knowledge
    if ($cookingOutside -notmatch 'nấu ăn.*ngoài phạm vi' -or $weatherOutside -notmatch 'Thời tiết.*ngoài phạm vi' -or $cookingOutside -eq $weatherOutside) {
        Add-AssistantVerificationError 'Out-of-scope replies are not adapted to their question context.'
    }
    if ($relatedUnknown -match 'không liên quan đến Tool|không thuộc Tool Kiểm Tra|ngoài phạm vi Tool') {
        Add-AssistantVerificationError 'A Tool-related question was incorrectly rejected as out of scope.'
    }
    $scopeInjectionKnowledge = (Get-Content -LiteralPath $knowledgePath -Raw -Encoding UTF8) | ConvertFrom-Json
    $scopeInjectionKnowledge.Entries[0].Keywords = @($scopeInjectionKnowledge.Entries[0].Keywords) + @('cach nau bun bo hue')
    $scopeGuardedAnswer = Get-ToolAssistantAnswer -Question 'cách nấu bún bò huế' -Culture 'vi-VN' -Knowledge $scopeInjectionKnowledge
    if ($scopeGuardedAnswer -notmatch 'ngoài phạm vi Tool') {
        Add-AssistantVerificationError 'A high-scoring injected keyword bypassed the Tool-only scope gate.'
    }

    $learningAnswer = Get-ToolAssistantAnswer -Question 'trợ lý học hỏi liên tục mà không tăng dung lượng exe như thế nào' -Culture 'vi-VN' -Knowledge $knowledge
    if ($learningAnswer -notmatch 'cache rời' -or $learningAnswer -notmatch 'không làm tăng EXE' -or $learningAnswer -notmatch 'không được gửi đi') {
        Add-AssistantVerificationError 'The signed external-knowledge architecture is not explained accurately.'
    }

    $pluginAnswer = Get-ToolAssistantAnswer -Question 'cách cài plugin json chỉ đọc' -Culture 'vi-VN' -Knowledge $knowledge
    $formatAnswer = Get-ToolAssistantAnswer -Question 'tool có xuất báo cáo docx không' -Culture 'vi-VN' -Knowledge $knowledge
    if ($pluginAnswer -notmatch 'nguồn tin cậy' -or $formatAnswer -notmatch 'không xuất DOCX') {
        Add-AssistantVerificationError 'Feature 10 subfeatures or report-format questions are not answered specifically.'
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
            LastQuestionKey=''; LastQuestionText=''; LastAnswer=''; OnlineMode=$false
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
        if ($testChat.Controls.Count -ne 0 -or $testState.Transcript.Length -ne 0 -or
            -not [string]::IsNullOrEmpty([string]$testState.LastQuestionText)) {
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
    foreach ($requiredToken in @('$send.Tag = $assistantState','Queue-ToolAssistantQuestion -State $sender.Tag','$eventArgs.Handled = $true','BeginInvoke','SubmissionQueued','ConnectOnline','ConnectOnlineTip','Update-ToolAssistantConnectionUi','Update-ToolAssistantConversationUi','Complete-ToolAssistantConversationLayout','Set-ToolAssistantHeaderBounds','Set-ToolAssistantInputFrameState','InputIdleBorderColor','UserBubbleBorderColor','AssistantBubbleBorderColor','RenderTimer','PendingRevealControl','RevealQueued','[Windows.Forms.Application]::DoEvents()','Windows.Forms.FlowLayoutPanel','Windows.Forms.TableLayoutPanel','Role User','Role Assistant','IsSubmitting','SendButton.Enabled','Expand-ToolAssistantContextQuery','Test-ToolAssistantRelatedQuery','Get-ToolAssistantDocumentAnswer','LastQuestionText','KnowledgePlusBundledDocumentation','Test-ToolAssistantKnowledgeSignature','DetachedCmsSha256PinnedCertificate','Save-ToolAssistantSignedKnowledgeCache','remoteVersion -lt $currentVersion','Invoke-ToolAssistantKnowledgeSyncUi')) {
        if (-not $assistantSource.Contains($requiredToken)) { Add-AssistantVerificationError "Assistant UI interaction token missing: $requiredToken" }
    }
    if ($assistantSource.Contains('New-Object Windows.Forms.RichTextBox')) {
        Add-AssistantVerificationError 'Assistant conversation still uses a shared RichTextBox instead of separate bubbles.'
    }
    if ($assistantSource -match '"Scope"[^\r\n]+(?:paid API|API trả phí|Codex)') {
        Add-AssistantVerificationError 'Assistant scope line still contains API/Codex promotional text.'
    }
    $expectedScopeVi = 'Hỗ trợ giải đáp các câu hỏi trong phạm vi Tool dựa trên dữ liệu cục bộ sẵn có.'
    $expectedScopeEn = "Supports questions within the Tool's scope using available local data."
    $expectedWelcomeVi = 'Trợ lý Tool hỗ trợ tra cứu, giải đáp và hướng dẫn các nội dung thuộc phạm vi Tool Kiểm Tra dựa trên kho tri thức, tài liệu hướng dẫn và dữ liệu báo cáo hiện có.'
    $expectedWelcomeEn = "Tool Assistant supports lookup, answers, and guidance for content within Tool Kiem Tra's scope, based on its knowledge base, user guides, and available report data."
    if ((Get-ToolAssistantUiText -Key Scope -Culture 'vi-VN') -ne $expectedScopeVi -or
        (Get-ToolAssistantUiText -Key Scope -Culture 'en-US') -ne $expectedScopeEn -or
        (Get-ToolAssistantUiText -Key Welcome -Culture 'vi-VN') -ne $expectedWelcomeVi -or
        (Get-ToolAssistantUiText -Key Welcome -Culture 'en-US') -ne $expectedWelcomeEn) {
        Add-AssistantVerificationError 'Assistant scope/welcome wording does not match the approved professional copy.'
    }
    if ((Get-ToolAssistantUiText -Key Welcome -Culture 'vi-VN') -match 'Bạn (?:có thể|cứ) (?:đặt câu hỏi|hỏi)' -or
        (Get-ToolAssistantUiText -Key Welcome -Culture 'en-US') -match 'Ask in your own words') {
        Add-AssistantVerificationError 'Assistant welcome still contains the removed invitation-to-ask sentence.'
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
    if ([string]$vi.'about.technology.body' -notlike "*$expectedWelcomeVi*" -or
        [string]$en.'about.technology.body' -notlike "*$expectedWelcomeEn*") {
        Add-AssistantVerificationError 'Product information does not use the approved professional Assistant wording.'
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
Write-Host 'VERIFY-ASSISTANT: 0 errors (400+ phrasings + signed external knowledge + rollback protection + Tool-only scope + local privacy + context follow-up + immediate bubbles + Send/Enter + live Online state).' -ForegroundColor Green
exit 0
