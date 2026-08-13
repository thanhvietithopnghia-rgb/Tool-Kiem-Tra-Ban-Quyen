$script:ToolAssistantSchemaVersion = "1.1"
$script:ToolAssistantToolVersion = "4.8.0.0"
$script:ToolAssistantMinimumKnowledgeVersion = [Version]"1.2.0"
$script:ToolAssistantKnowledgeFileName = "tool-assistant-knowledge-v1.1.json"
$script:ToolAssistantKnowledgeUrl = "https://raw.githubusercontent.com/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/tool-assistant-knowledge-v1.1.json"
$script:ToolAssistantMaxKnowledgeBytes = 2097152
$script:ToolAssistantMaxReportBytes = 10485760
$script:ToolAssistantDocumentCache = @{}

function Get-ToolAssistantMetadata {
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:ToolAssistantSchemaVersion
        ToolVersion = $script:ToolAssistantToolVersion
        Scope = "Tool-Kiem-Tra"
        Engine = "LocalKnowledge"
        PaidApiRequired = $false
        CodexRequired = $false
        DefaultNetworkMode = "Offline"
        OnlineTransfer = "DownloadOnlyKnowledgeJson"
        ReportUpload = $false
        AutomaticRemediation = $false
        PortableEveryMachine = $true
        CentralServerRequired = $false
        KnowledgeStorage = "BundledAndPerUserLocalCache"
        ReportContextSource = "CurrentDeviceLocalReportOnly"
        CoverageMode = "KnowledgePlusBundledDocumentation"
        ContextAwareFollowUp = $true
        ContextualOutOfScope = $true
        KnowledgeCompatibilityEnforced = $true
        KnowledgeFileName = $script:ToolAssistantKnowledgeFileName
    }
}

function ConvertTo-ToolAssistantSearchKey {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace([string]$Value)) { return "" }
    $decomposed = ([string]$Value).Normalize([Text.NormalizationForm]::FormD)
    $builder = New-Object Text.StringBuilder
    foreach ($character in $decomposed.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$builder.Append($character)
        }
    }
    $plain = $builder.ToString().Replace([char]0x0111, 'd').Replace([char]0x0110, 'D').ToLowerInvariant()
    $key = ([regex]::Replace($plain, '[^a-z0-9]+', ' ')).Trim()
    # Mo rong viet tat va loi go pho bien theo token doc lap, khong sua ten
    # san pham hay ma loi nam ben trong mot chuoi dai hon.
    $replacements = [ordered]@{
        'k'='khong'; 'ko'='khong'; 'kh'='khong'; 'dc'='duoc'; 'dk'='duoc'
        'tl'='tra loi'; 'pm'='phan mem'; 'bc'='bao cao'; 'csdl'='co so du lieu'
        'pb'='phien ban'; 'cn'='chuc nang'; 'hd'='huong dan'; 'sd'='su dung'
        'hdsd'='huong dan su dung'; 'pfd'='pdf'; 'ofline'='offline'; 'offine'='offline'
        'fixx'='sua'; 'fix'='sua'; 'kt'='kiem tra'; 'ktra'='kiem tra'; 'kieu'='kieu'
    }
    $tokens = @($key -split ' ' | Where-Object { $_ })
    $expanded = New-Object System.Collections.Generic.List[string]
    foreach ($token in $tokens) {
        if ($replacements.Contains($token)) {
            foreach ($replacementToken in ([string]$replacements[$token] -split ' ')) { [void]$expanded.Add($replacementToken) }
        } else { [void]$expanded.Add($token) }
    }
    return ($expanded -join ' ').Trim()
}

function Get-ToolAssistantCacheDirectory {
    $localAppData = [Environment]::GetFolderPath([Environment+SpecialFolder]::LocalApplicationData)
    if ([string]::IsNullOrWhiteSpace($localAppData)) { $localAppData = [string]$env:LOCALAPPDATA }
    if ([string]::IsNullOrWhiteSpace($localAppData)) { return "" }
    return Join-Path $localAppData "ThanhViet-Tool-Kiem-Tra\assistant"
}

function Get-ToolAssistantCachePath {
    $directory = Get-ToolAssistantCacheDirectory
    if ([string]::IsNullOrWhiteSpace($directory)) { return "" }
    return Join-Path $directory $script:ToolAssistantKnowledgeFileName
}

function Test-ToolAssistantKnowledge {
    param([AllowNull()][object]$Knowledge)

    if ($null -eq $Knowledge) { return $false }
    if ([string]$Knowledge.SchemaVersion -ne $script:ToolAssistantSchemaVersion) { return $false }
    try {
        if ([Version]([string]$Knowledge.KnowledgeVersion) -lt $script:ToolAssistantMinimumKnowledgeVersion) { return $false }
    } catch { return $false }
    if ([string]$Knowledge.Scope -ne "Tool-Kiem-Tra") { return $false }
    try {
        $toolVersion = [Version]$script:ToolAssistantToolVersion
        $minimumToolVersion = [Version]([string]$Knowledge.ToolVersionMin)
        $maximumToolVersion = [Version]([string]$Knowledge.ToolVersionMax)
        if ($toolVersion -lt $minimumToolVersion -or $toolVersion -gt $maximumToolVersion) { return $false }
        if ([string]$Knowledge.ReleasedWithToolVersion -ne $script:ToolAssistantToolVersion) { return $false }
    } catch { return $false }
    $entries = @($Knowledge.Entries)
    if ($entries.Count -lt 20 -or $entries.Count -gt 300) { return $false }
    $seen = @{}
    foreach ($entry in $entries) {
        $id = [string]$entry.Id
        if ([string]::IsNullOrWhiteSpace($id) -or $id -notmatch '^[a-z0-9-]{2,64}$' -or $seen.ContainsKey($id)) { return $false }
        if ([string]::IsNullOrWhiteSpace([string]$entry.AnswerVi) -or [string]::IsNullOrWhiteSpace([string]$entry.AnswerEn)) { return $false }
        if (@($entry.Keywords).Count -lt 2 -or @($entry.Keywords).Count -gt 80) { return $false }
        if ([string]$entry.AnswerVi -match '(?i)<script|powershell\s+-|cmd\.exe|javascript:') { return $false }
        if ([string]$entry.AnswerEn -match '(?i)<script|powershell\s+-|cmd\.exe|javascript:') { return $false }
        $seen[$id] = $true
    }
    return $true
}

function Read-ToolAssistantKnowledgeFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    try {
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($item.Length -le 16 -or $item.Length -gt $script:ToolAssistantMaxKnowledgeBytes) { return $null }
        $knowledge = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-ToolAssistantKnowledge -Knowledge $knowledge)) { return $null }
        return $knowledge
    } catch {
        return $null
    }
}

function Get-ToolAssistantKnowledge {
    $cachePath = Get-ToolAssistantCachePath
    if (-not [string]::IsNullOrWhiteSpace($cachePath)) {
        $cached = Read-ToolAssistantKnowledgeFile -Path $cachePath
        if ($cached) { return $cached }
    }
    return Read-ToolAssistantKnowledgeFile -Path (Join-Path $PSScriptRoot $script:ToolAssistantKnowledgeFileName)
}

function Get-ToolAssistantSyncText {
    param(
        [Parameter(Mandatory = $true)][string]$Key,
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN"
    )

    $english = [bool]($Culture -eq "en-US")
    switch ($Key) {
        "Offline" { if ($english) { return "Tool Assistant is Offline; local knowledge remains available." }; return "Trợ lý đang Offline; bộ tri thức cục bộ vẫn sẵn sàng." }
        "InvalidAddress" { if ($english) { return "The synchronization address is invalid." }; return "Địa chỉ đồng bộ không hợp lệ." }
        "TooLarge" { if ($english) { return "The knowledge file exceeds the safety limit." }; return "Tệp tri thức vượt giới hạn an toàn." }
        "InvalidKnowledge" { if ($english) { return "The knowledge file has an invalid structure or unsafe content." }; return "Tệp tri thức không đúng cấu trúc hoặc chứa nội dung không an toàn." }
        "NoDataFolder" { if ($english) { return "The user data folder could not be determined." }; return "Không xác định được thư mục dữ liệu người dùng." }
        "Updated" { if ($english) { return "Tool Assistant knowledge has been synchronized." }; return "Đã đồng bộ bộ tri thức Trợ lý Tool." }
        "Failed" { if ($english) { return "Synchronization failed; Tool Assistant continues with local knowledge." }; return "Không đồng bộ được; Trợ lý tiếp tục dùng bộ tri thức cục bộ." }
        default { return $Key }
    }
}

function Sync-ToolAssistantKnowledge {
    param(
        [Parameter(Mandatory = $true)][bool]$OnlineMode,
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN"
    )

    if (-not $OnlineMode) {
        return [pscustomobject]@{ Success=$false; Updated=$false; Code="Offline"; Message=(Get-ToolAssistantSyncText -Key "Offline" -Culture $Culture) }
    }
    try {
        $uri = New-Object Uri($script:ToolAssistantKnowledgeUrl)
        if ($uri.Scheme -ne "https" -or $uri.Host -ne "raw.githubusercontent.com" -or
            $uri.AbsolutePath -ne "/thanhvietithopnghia-rgb/Tool-Kiem-Tra-Ban-Quyen/main/tool-assistant-knowledge-v1.1.json") {
            throw (Get-ToolAssistantSyncText -Key "InvalidAddress" -Culture $Culture)
        }
        $request = [Net.HttpWebRequest]::Create($uri)
        $request.Method = "GET"
        $request.Timeout = 8000
        $request.ReadWriteTimeout = 8000
        $request.AllowAutoRedirect = $false
        $request.UserAgent = "ThanhViet-Tool-Kiem-Tra/$($script:ToolAssistantToolVersion)"
        $response = $request.GetResponse()
        try {
            if ($response.ContentLength -gt $script:ToolAssistantMaxKnowledgeBytes) { throw (Get-ToolAssistantSyncText -Key "TooLarge" -Culture $Culture) }
            $reader = New-Object IO.StreamReader($response.GetResponseStream(), (New-Object Text.UTF8Encoding($false)), $true)
            try { $json = $reader.ReadToEnd() } finally { $reader.Dispose() }
        } finally {
            $response.Dispose()
        }
        if ([Text.Encoding]::UTF8.GetByteCount($json) -gt $script:ToolAssistantMaxKnowledgeBytes) { throw (Get-ToolAssistantSyncText -Key "TooLarge" -Culture $Culture) }
        $knowledge = $json | ConvertFrom-Json -ErrorAction Stop
        if (-not (Test-ToolAssistantKnowledge -Knowledge $knowledge)) { throw (Get-ToolAssistantSyncText -Key "InvalidKnowledge" -Culture $Culture) }
        $directory = Get-ToolAssistantCacheDirectory
        if ([string]::IsNullOrWhiteSpace($directory)) { throw (Get-ToolAssistantSyncText -Key "NoDataFolder" -Culture $Culture) }
        if (-not (Test-Path -LiteralPath $directory -PathType Container)) { New-Item -ItemType Directory -Path $directory -Force | Out-Null }
        $cachePath = Get-ToolAssistantCachePath
        [IO.File]::WriteAllText($cachePath, $json, (New-Object Text.UTF8Encoding($false)))
        return [pscustomobject]@{ Success=$true; Updated=$true; Code="Updated"; Message=(Get-ToolAssistantSyncText -Key "Updated" -Culture $Culture) }
    } catch {
        $failure = Get-ToolAssistantSyncText -Key "Failed" -Culture $Culture
        return [pscustomobject]@{ Success=$false; Updated=$false; Code="SyncFailed"; Message="$failure $($_.Exception.Message)" }
    }
}

function Get-ToolAssistantTokenDistance {
    param([string]$Left, [string]$Right)

    if ($Left -eq $Right) { return 0 }
    if ([string]::IsNullOrEmpty($Left)) { return $Right.Length }
    if ([string]::IsNullOrEmpty($Right)) { return $Left.Length }
    if ([Math]::Abs($Left.Length - $Right.Length) -gt 1) { return 99 }
    $previous = New-Object 'int[]' ($Right.Length + 1)
    $current = New-Object 'int[]' ($Right.Length + 1)
    for ($j = 0; $j -le $Right.Length; $j++) { $previous[$j] = $j }
    for ($i = 1; $i -le $Left.Length; $i++) {
        $current[0] = $i
        for ($j = 1; $j -le $Right.Length; $j++) {
            $cost = if ($Left[$i - 1] -eq $Right[$j - 1]) { 0 } else { 1 }
            $current[$j] = [Math]::Min([Math]::Min(($current[$j - 1] + 1), ($previous[$j] + 1)), ($previous[$j - 1] + $cost))
        }
        $swap = $previous; $previous = $current; $current = $swap
    }
    return $previous[$Right.Length]
}

function Test-ToolAssistantFollowUpQuery {
    param([Parameter(Mandatory = $true)][string]$QueryKey)

    if ([string]::IsNullOrWhiteSpace($QueryKey)) { return $false }
    if ($QueryKey -match '^(?:con|the con|vay|vay con|no|cai nay|cai do|muc nay|muc do|chuc nang nay|chuc nang do|truong hop nay|truong hop do)\b') { return $true }
    if ($QueryKey -match '^(?:cach dung no|su dung no|lam sao dung|noi ro hon|chi tiet hon|giai thich them|tai sao vay|sao nua|tiep theo)\b') { return $true }
    $tokens = @($QueryKey -split ' ' | Where-Object { $_ })
    return [bool]($tokens.Count -le 4 -and $QueryKey -match '\b(?:no|nay|do|them|tiep|con)\b')
}

function Expand-ToolAssistantContextQuery {
    param(
        [Parameter(Mandatory = $true)][string]$QueryKey,
        [AllowNull()][string]$PreviousQuestion
    )

    if ([string]::IsNullOrWhiteSpace([string]$PreviousQuestion) -or -not (Test-ToolAssistantFollowUpQuery -QueryKey $QueryKey)) {
        return $QueryKey
    }
    $previousKey = ConvertTo-ToolAssistantSearchKey -Value $PreviousQuestion
    if ([string]::IsNullOrWhiteSpace($previousKey)) { return $QueryKey }
    return ($QueryKey + ' ' + $previousKey).Trim()
}

function Test-ToolAssistantRelatedQuery {
    param(
        [Parameter(Mandatory = $true)][string]$QueryKey,
        [AllowNull()][string]$PreviousQuestion
    )

    if ($QueryKey -match '\b(?:tool|cong cu|tro ly|dashboard|bao cao|quet|scan|windows|office|phan mem|ung dung|may chu|may tram|server|client|pdf|json|html|xml|docx|kms|activator|backup|sao luu|khoi phuc|cap nhat|loi|uac|administrator|catalog|catalogue|oem|firmware|ban quyen|kich hoat|smartscreen|defender|sha256|hash|chu ky|chung chi|certificate|plugin|timeline|offline|online|dry run|forensic|giao dien|cai dat|chuc nang|nut|muc)\b') { return $true }
    if ($QueryKey -match '^(?:phien ban|version|do ai phat trien|ai phat trien|tac gia|ngay phat hanh|ngay build|tom tat|noi dung chinh|muc dich|nguyen tac|cong nghe|yeu cau he thong|cach chay|cach cai|tai o dau)\b') { return $true }
    if (-not [string]::IsNullOrWhiteSpace([string]$PreviousQuestion) -and (Test-ToolAssistantFollowUpQuery -QueryKey $QueryKey)) {
        $previousKey = ConvertTo-ToolAssistantSearchKey -Value $PreviousQuestion
        return Test-ToolAssistantRelatedQuery -QueryKey $previousKey -PreviousQuestion $null
    }
    return $false
}

function ConvertTo-ToolAssistantPlainDocumentLine {
    param([AllowNull()][string]$Line)

    $text = ([string]$Line).Trim()
    if ([string]::IsNullOrWhiteSpace($text) -or $text -match '^```') { return '' }
    $text = $text -replace '!\[[^\]]*\]\([^\)]*\)', ''
    $text = $text -replace '\[([^\]]+)\]\([^\)]+\)', '$1'
    $text = $text -replace '\*\*([^\*]+)\*\*', '$1'
    $text = $text -replace '`([^`]+)`', '$1'
    $text = $text -replace '^[-*]\s+', '- '
    return $text.Trim()
}

function Get-ToolAssistantDocumentSections {
    param([ValidateSet('vi-VN','en-US')][string]$Culture = 'vi-VN')

    if ($script:ToolAssistantDocumentCache.ContainsKey($Culture)) {
        return @($script:ToolAssistantDocumentCache[$Culture])
    }
    $fileName = if ($Culture -eq 'en-US') { 'USER-GUIDE-en-US.md' } else { 'HUONG-DAN.txt' }
    $path = Join-Path $PSScriptRoot $fileName
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $script:ToolAssistantDocumentCache[$Culture] = @()
        return @()
    }
    try { $raw = Get-Content -LiteralPath $path -Raw -Encoding UTF8 -ErrorAction Stop } catch {
        $script:ToolAssistantDocumentCache[$Culture] = @()
        return @()
    }
    $sections = New-Object System.Collections.Generic.List[object]
    $matches = [regex]::Matches($raw, '(?ms)^#{2,3}[ \t]+([^\r\n]+)\r?\n(.*?)(?=^#{2,3}[ \t]+|\z)')
    foreach ($match in $matches) {
        $heading = ConvertTo-ToolAssistantPlainDocumentLine -Line ([string]$match.Groups[1].Value)
        $body = [string]$match.Groups[2].Value
        if ([string]::IsNullOrWhiteSpace($heading) -or [string]::IsNullOrWhiteSpace($body)) { continue }
        $searchKey = ConvertTo-ToolAssistantSearchKey -Value ($heading + ' ' + $body)
        [void]$sections.Add([pscustomobject]@{ Heading=$heading; Body=$body; HeadingKey=(ConvertTo-ToolAssistantSearchKey -Value $heading); SearchKey=$searchKey })
    }
    $result = @($sections.ToArray())
    $script:ToolAssistantDocumentCache[$Culture] = $result
    return $result
}

function Get-ToolAssistantDocumentAnswer {
    param(
        [Parameter(Mandatory = $true)][string]$QueryKey,
        [ValidateSet('vi-VN','en-US')][string]$Culture = 'vi-VN'
    )

    $stopTokens = @('bo','cua','cho','voi','nay','kia','mot','nhung','cac','the','nao','gi','la','va','theo','all','duoc','khong','co','hay','minh','toi','ban','tool','cong','cu')
    $queryTokens = @($QueryKey -split ' ' | Where-Object { $_.Length -ge 2 -and $_ -notin $stopTokens } | Select-Object -Unique)
    if ($queryTokens.Count -eq 0) { return '' }
    $best = $null
    $bestScore = 0
    foreach ($section in @(Get-ToolAssistantDocumentSections -Culture $Culture)) {
        $score = 0
        if ($QueryKey.Contains([string]$section.HeadingKey) -or ([string]$section.HeadingKey).Contains($QueryKey)) { $score += 90 }
        foreach ($token in $queryTokens) {
            if (([string]$section.HeadingKey -split ' ') -contains $token) { $score += 14 }
            elseif (([string]$section.SearchKey -split ' ') -contains $token) { $score += 3 }
            elseif ($token.Length -ge 5 -and ([string]$section.HeadingKey).Contains($token)) { $score += 7 }
        }
        if ($QueryKey -match '\b(?:cach|huong dan|su dung|thao tac|cac buoc|lam sao)\b' -and [string]$section.Body -match '(?m)^\s*1\.') { $score += 8 }
        if ($score -gt $bestScore) { $bestScore = $score; $best = $section }
    }
    if ($null -eq $best -or $bestScore -lt 24) { return '' }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($rawLine in ([string]$best.Body -split '\r?\n')) {
        $line = ConvertTo-ToolAssistantPlainDocumentLine -Line $rawLine
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.Length -gt 360) { $line = $line.Substring(0, 357).TrimEnd() + '...' }
        [void]$selected.Add($line)
        if ($selected.Count -ge 9 -or (($selected -join "`r`n").Length -ge 1300)) { break }
    }
    if ($selected.Count -eq 0) { return '' }
    $prefix = if ($Culture -eq 'en-US') { "For '$([string]$best.Heading)':" } else { "Về mục '$([string]$best.Heading)':" }
    return ($prefix + "`r`n" + ($selected -join "`r`n"))
}

function Get-ToolAssistantEntryScore {
    param([Parameter(Mandatory = $true)][string]$QueryKey, [Parameter(Mandatory = $true)][object]$Entry)

    $stopTokens = @('bo','cua','cho','voi','nay','kia','mot','nhung','cac','the','nao','gi','la','va','theo','all','duoc','khong','co','hay','minh','toi','ban')
    $queryTokens = @($QueryKey -split ' ' | Where-Object { $_.Length -ge 2 -and $_ -notin $stopTokens } | Select-Object -Unique)
    $keywordTokenSet = @{}
    $phraseScore = 0
    foreach ($keywordValue in @($Entry.Keywords)) {
        $keyword = ConvertTo-ToolAssistantSearchKey -Value ([string]$keywordValue)
        if ([string]::IsNullOrWhiteSpace($keyword)) { continue }
        if ($QueryKey -eq $keyword) { return (10000 + $keyword.Length) }
        if ($QueryKey.Contains($keyword)) {
            $candidateScore = if ($keyword.Contains(' ')) { 220 + $keyword.Length } elseif ($keyword.Length -ge 4) { 48 + $keyword.Length } else { 12 }
            if ($candidateScore -gt $phraseScore) { $phraseScore = $candidateScore }
        }
        $keywordTokens = @($keyword -split ' ' | Where-Object { $_.Length -ge 2 -and $_ -notin $stopTokens })
        foreach ($keywordToken in $keywordTokens) { $keywordTokenSet[$keywordToken] = $true }
    }
    $score = $phraseScore
    foreach ($queryToken in $queryTokens) {
        if ($keywordTokenSet.ContainsKey($queryToken)) {
            $score += 7
            continue
        }
        if ($queryToken.Length -ge 4) {
            foreach ($keywordToken in @($keywordTokenSet.Keys)) {
                if ($keywordToken.Length -ge 4 -and (Get-ToolAssistantTokenDistance -Left $queryToken -Right $keywordToken) -le 1) {
                    $score += 1
                    break
                }
            }
        }
    }
    return $score
}

function Get-ToolAssistantPriorityEntryId {
    param([Parameter(Mandatory = $true)][string]$QueryKey)

    if ($QueryKey -match '(?:tool|cong cu).*(?:phien ban|version)|(?:phien ban|version).*(?:tool|cong cu|hien tai|dang dung|moi nhat|bay gio)|^(?:phien ban|version)(?: hien tai| moi nhat)?$') { return 'tool-version' }
    if ($QueryKey -match '(?:tac gia|author|nguoi phat trien|developer)|(?:do ai|ai).*(?:phat trien|viet|tao ra|lam ra)') { return 'tool-author' }
    if ($QueryKey -match '(?:ngay|thoi diem).*(?:phat hanh|ra mat|build)|(?:phat hanh|ra mat|build).*(?:ngay nao|khi nao|luc nao)') { return 'release-date' }
    if ($QueryKey -match '(?:tom tat|noi dung chinh|gioi thieu ngan|tong quan|tool lam gi|cong cu lam gi|muc dich cua tool)') { return 'tool-overview' }
    if ($QueryKey -match '(?:nguyen tac|triet ly|tieu chi).*(?:tool|cong cu|hoat dong|an toan)|^(?:nguyen tac|triet ly|tieu chi)(?: cua tool)?$') { return 'tool-principles' }
    if ($QueryKey -match '(?:tat ca|toan bo|10|tung).*(?:chuc nang|tinh nang|tac vu)|(?:chuc nang|tinh nang).*(?:gom nhung gi|co gi|danh sach|tong hop|tom tat)') { return 'feature-overview' }
    if ($QueryKey -match '(?:cach chay|khoi dong tool|bat tool|mo tool|bat dau su dung|lan dau su dung|huong dan nhanh|getting started)') { return 'getting-started' }
    if ($QueryKey -match '(?:yeu cau he thong|cau hinh toi thieu|windows nao chay duoc|he dieu hanh ho tro|tuong thich windows|32 bit|64 bit|powershell may|\.net framework)') { return 'system-requirements' }
    if ($QueryKey -match '(?:cong nghe|ngon ngu lap trinh|viet bang gi|nen tang|winforms|anycpu|kien truc cua tool)') { return 'technology' }
    if ($QueryKey -match '(?:doi ngon ngu|tieng viet|english|sang toi|light dark|giao dien|cai dat).*(?:tool|chuyen|doi|chon|mau|ngon ngu)|(?:cach doc man hinh chinh)') { return 'interface-settings' }
    if ($QueryKey -match '(?:dung tac vu|huy tac vu|nut dung|quet bi lau|quet bi treo|khac phuc bi dung)') { return 'stop-task' }
    if ($QueryKey -match '(?:sao luu|backup|khoi phuc backup|restore backup|phuc hoi backup)') { return 'backup-restore' }
    if ($QueryKey -match '(?:khong mo duoc|khong chay duoc|khong khoi dong duoc).*(?:exe|tool|cong cu)|(?:exe|tool|cong cu).*(?:bi chan|khong mo|khong chay|khong khoi dong)') { return 'launch-troubleshooting' }
    if ($QueryKey -match '(?:khong thay|thieu|bo sot).*(?:phan mem|ung dung)|(?:phan mem|ung dung).*(?:khong hien|khong duoc tim thay|bi thieu)') { return 'software-not-found' }
    if ($QueryKey -match '(?:khong tao duoc|tao that bai|bi loi).*(?:pdf)|(?:pdf).*(?:khong tao|that bai|bi loi)') { return 'report-pdf-failure' }
    if ($QueryKey -match '(?:online).*(?:loi|that bai|khong ket noi|khong cap nhat|khong dong bo)|(?:khong ket noi|khong cap nhat|khong dong bo).*(?:online|internet)') { return 'online-troubleshooting' }
    if ($QueryKey -match '(?:may chu|server).*(?:tao cau hinh|xoa cau hinh|khoi dong|dung may chu|ma ghep noi|url acl|firewall)|(?:tao|xoa|khoi dong|dung).*(?:cau hinh may chu|server)') { return 'enterprise-server-management' }
    if ($QueryKey -match '(?:may tram|client|workstation).*(?:ghep noi|gui bao cao|agent|tu tim)|(?:ghep noi|gui bao cao|chay agent).*(?:may tram|client)') { return 'enterprise-client-management' }
    if ($QueryKey -match '(?:kenh ho tro|lien he tac gia|email ho tro|zalo ho tro|can ho tro tool)') { return 'support-channel' }
    if ($QueryKey -match '(?:plugin|quy tac mo rong).*(?:cai|kiem tra|danh gia|json|thu muc|an toan)|(?:cai|danh gia).*(?:plugin)') { return 'plugin-management' }
    if ($QueryKey -match '(?:chung chi|certificate|authenticode).*(?:windows|office|kiem tra|xac minh)|(?:kiem tra).*(?:chung chi so|certificate)') { return 'certificate-audit' }
    if ($QueryKey -match '(?:timeline|dong thoi gian|lich su thay doi).*(?:ban quyen|xac minh|xuat)|(?:xac minh|xuat).*(?:timeline)') { return 'license-timeline' }
    if ($QueryKey -match '(?:huong dan su dung|tai lieu huong dan|lich su phien ban).*(?:mo|xem|o dau|html|pdf)|(?:mo|xem).*(?:huong dan chi tiet|lich su phien ban)') { return 'embedded-documents' }
    if ($QueryKey -match '(?:dinh dang|loai tep|file nao|docx|word).*(?:bao cao|xuat)|(?:bao cao).*(?:json|xml|html|pdf|docx|dinh dang)') { return 'report-formats' }
    $functionRoutes = [ordered]@{
        '10'='report-center'; '9'='deep-scan'; '8'='enterprise'; '7'='oem'; '6'='remediation'
        '5'='software'; '4'='office-license'; '3'='windows-license'; '2'='hardware'; '1'='scan-all'
    }
    foreach ($number in $functionRoutes.Keys) {
        if ($QueryKey -match "\b(?:chuc nang|muc|nut|function)(?: so)? $number\b") { return [string]$functionRoutes[$number] }
    }
    if ($QueryKey -match '(?:bo qua|vo hieu|tat|lach).*(?:ban quyen|kich hoat|defender|antivirus)|(?:crack|keygen).*(?:cach lam|huong dan|tai o dau)') { return 'safe-boundary' }
    if ($QueryKey -match '(?:co so du lieu|kho tri thuc|du lieu tro ly).*(?:cap nhat|dong bo|phien ban|tuong thich)|(?:cap nhat|dong bo).*(?:co so du lieu|kho tri thuc|du lieu tro ly)') { return 'assistant-knowledge-update' }
    if ($QueryKey -match '(?:pdf|bao cao).*(?:mat dong|khuyet dong|cat chu|be chu|gian dong|khoang cach dong|chieu cao hang|bang rong|bo cuc)|(?:mat dong|khuyet dong|cat chu).*(?:pdf|bao cao)') { return 'report-pdf' }
    if ($QueryKey -match '(?:phan mem he thong|phan mem mac dinh|system software|system component).*(?:an|hien|show|danh sach|pdf)|(?:an|hien).*(?:phan mem he thong|phan mem mac dinh)') { return 'software-system-filter' }
    if ($QueryKey -match '(?:mot thu muc|thu muc chung|khong tao thu muc con|gom.*bao cao|json.*html.*pdf|html.*pdf.*json)') { return 'report-shared-folder' }
    if ($QueryKey -match '(?:catalog|catalogue|danh muc phan mem|nhan dien phan mem).*(?:mo rong|cap nhat|them|quet|nhieu)|(?:quet|nhan dien).*(?:nhieu phan mem|danh muc phan mem)') { return 'software-catalog' }
    if ($QueryKey -match '(?:trung|lap|duplicate|nhieu dong).*(?:phan mem|ung dung)|(?:gop|hop nhat).*(?:phan mem|ket qua)') { return 'duplicate-software' }
    if ($QueryKey -match '(?:hashmismatch|hash mismatch|chu ky sai|toan ven tep|tep bi sua|file integrity)') { return 'integrity-compromised' }
    if ($QueryKey -match '(?:may chu|may tram|server|client).*(?:timeout|khong ket noi|loi ket noi|cong bi chan|firewall|dich vu chua chay|ma ghep noi)') { return 'enterprise-connection-errors' }
    if ($QueryKey -match '(?:tu tim may chu|tim may chu|do may|quet may|khong thay may|discovery|scan lan)') { return 'enterprise-discovery' }
    if ($QueryKey -match '(?:online|offline).*(?:lan|may chu noi bo|internet)|(?:lan|may chu noi bo).*(?:online|offline)') { return 'enterprise-network-mode' }
    if ($QueryKey -match '\b0xc004d302\b|chua xac dinh|khong the xac minh|khong doc duoc du lieu cap phep|du lieu cap phep loi') { return 'unverifiable' }
    if ($QueryKey -match '\b0x[0-9a-f]{4,}\b|\bma loi\b|\berror code\b') { return 'error-codes' }
    if ($QueryKey -match 'chua du bang chung|kiem tra thu cong|manual review|can xem lai|chua chac chan') { return 'manual-review' }
    if ($QueryKey -match '(?:bao cao|ket qua).*(?:khang dinh|ket luan chac|chung minh|hop phap|chinh hang|ban quyen)|(?:khang dinh|chung minh).*(?:bao cao|ket qua)') { return 'report-legal-limit' }
    if ($QueryKey -match 'doc bao cao|cach doc|giai thich ket luan|hieu ket luan|muc rui ro|bang chung.*bao cao|report evidence') { return 'report-evidence' }
    if ($QueryKey -match 'bao cao luu o dau|thu muc bao cao|tim bao cao|mo bao cao|report folder|where.*report') { return 'report-center' }
    if ($QueryKey -match 'khac phuc.*(?:kms|activator|crack)|xoa.*(?:kms|activator|crack)|go.*(?:kms|activator|crack)') { return 'remediation' }
    if ($QueryKey -match '\b(?:kms|activator|autokms|rearm|hwidgen)\b') { return 'kms-activator' }
    return ''
}

function Resolve-ToolAssistantEntry {
    param(
        [Parameter(Mandatory = $true)][string]$QueryKey,
        [Parameter(Mandatory = $true)][object]$Knowledge
    )

    foreach ($entry in @($Knowledge.Entries)) {
        foreach ($keywordValue in @($entry.Keywords)) {
            if ($QueryKey -eq (ConvertTo-ToolAssistantSearchKey -Value ([string]$keywordValue))) {
                return [pscustomobject]@{ Entry=$entry; Score=(10000 + $QueryKey.Length); Route='ExactKeyword' }
            }
        }
    }
    $priorityId = Get-ToolAssistantPriorityEntryId -QueryKey $QueryKey
    if (-not [string]::IsNullOrWhiteSpace($priorityId)) {
        $priorityEntry = @($Knowledge.Entries | Where-Object { [string]$_.Id -eq $priorityId } | Select-Object -First 1)
        if ($priorityEntry.Count -gt 0) {
            return [pscustomobject]@{ Entry=$priorityEntry[0]; Score=9000; Route='SpecificIntent' }
        }
    }
    $bestEntry = $null
    $bestScore = 0
    $secondEntry = $null
    $secondScore = 0
    foreach ($entry in @($Knowledge.Entries)) {
        $score = Get-ToolAssistantEntryScore -QueryKey $QueryKey -Entry $entry
        if ($score -gt $bestScore) {
            $secondScore = $bestScore; $secondEntry = $bestEntry
            $bestScore = $score; $bestEntry = $entry
        } elseif ($score -gt $secondScore) {
            $secondScore = $score; $secondEntry = $entry
        }
    }
    return [pscustomobject]@{
        Entry=$bestEntry; Score=$bestScore; Route='ScoredKeywords'
        SecondEntry=$secondEntry; SecondScore=$secondScore; Margin=($bestScore - $secondScore)
    }
}

function Resolve-ToolAssistantReportJsonPath {
    param([AllowNull()][string]$Path)

    try {
        if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
        $fullPath = [IO.Path]::GetFullPath($Path)
        if ($fullPath.StartsWith('\\', [StringComparison]::Ordinal)) { return "" }
        $pathRoot = [IO.Path]::GetPathRoot($fullPath)
        if (-not [string]::IsNullOrWhiteSpace($pathRoot)) {
            try {
                if ((New-Object IO.DriveInfo($pathRoot)).DriveType -eq [IO.DriveType]::Network) { return "" }
            } catch {}
        }
        if (Test-Path -LiteralPath $fullPath -PathType Container) {
            $candidate = Get-ChildItem -LiteralPath $fullPath -Filter "*.json" -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Length -le $script:ToolAssistantMaxReportBytes } |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1
            if ($candidate) { return [string]$candidate.FullName }
            return ""
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return "" }
        if ([IO.Path]::GetExtension($fullPath) -ieq ".json") { return $fullPath }
        $directory = Split-Path -Parent $fullPath
        $baseName = [IO.Path]::GetFileNameWithoutExtension($fullPath)
        $sameName = Join-Path $directory ($baseName + ".json")
        if (Test-Path -LiteralPath $sameName -PathType Leaf) { return $sameName }
        return Resolve-ToolAssistantReportJsonPath -Path $directory
    } catch {
        return ""
    }
}

function Get-ToolAssistantReportContext {
    param([AllowNull()][string]$ReportPath)

    $jsonPath = Resolve-ToolAssistantReportJsonPath -Path $ReportPath
    if ([string]::IsNullOrWhiteSpace($jsonPath)) { return $null }
    try {
        $item = Get-Item -LiteralPath $jsonPath -Force -ErrorAction Stop
        if ($item.Length -le 2 -or $item.Length -gt $script:ToolAssistantMaxReportBytes) { return $null }
        $report = Get-Content -LiteralPath $jsonPath -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace([string]$report.SchemaVersion) -or
            [string]::IsNullOrWhiteSpace([string]$report.ReportKind) -or
            [string]::IsNullOrWhiteSpace([string]$report.CreatedAt)) { return $null }
        return [pscustomobject][ordered]@{
            Path = $jsonPath
            CreatedAt = [string]$report.CreatedAt
            Mode = [string]$report.Mode
            OfflineMode = [bool]$report.OfflineMode
            WindowsStatus = [string]$report.WindowsStatus
            WindowsChannel = [string]$report.WindowsChannel
            WindowsConclusionCode = [string]$report.WindowsConclusionCode
            WindowsConclusion = [string]$report.WindowsConclusion
            OfficeDetected = [bool]$report.OfficeDetected
            OfficeStatus = [string]$report.OfficeStatus
            OfficeConclusionCode = [string]$report.OfficeConclusionCode
            OfficeConclusion = [string]$report.OfficeConclusion
            SuspiciousFindingCount = [int]$report.SuspiciousFindingCount
            ManualReviewFindingCount = [int]$report.ManualReviewFindingCount
            ThirdPartyApplicationCount = [int]$report.ThirdPartyApplicationCount
            ThirdPartyHighSeverityCount = [int]$report.ThirdPartyHighSeverityCount
        }
    } catch {
        return $null
    }
}

function Get-ToolAssistantLocalizedConclusion {
    param(
        [Parameter(Mandatory = $true)][ValidateSet("Windows", "Office")][string]$Product,
        [AllowNull()][string]$Code,
        [AllowNull()][string]$Fallback,
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN"
    )

    $english = [bool]($Culture -eq "en-US")
    $isWindows = [bool]($Product -eq "Windows")
    switch ([string]$Code) {
        "NotScanned" { if ($english) { return "Not scanned in this report." }; return "Không được quét trong báo cáo này." }
        "NotDetected" { if ($english) { return "Microsoft Office was not detected." }; return "Không phát hiện Microsoft Office." }
        "Unverifiable" { if ($english) { return "Undetermined — licensing data could not be read." }; return "Chưa xác định — không đọc được dữ liệu cấp phép." }
        "NotLicensed" {
            if ($english) { return $(if ($isWindows) { "Windows is not licensed." } else { "Microsoft Office is not licensed." }) }
            return $(if ($isWindows) { "Windows chưa được cấp phép." } else { "Microsoft Office chưa được cấp phép." })
        }
        "KmsApprovedHost" { if ($english) { return "KMS activation was found on an approved host; entitlement records still need review." }; return "Phát hiện kích hoạt KMS qua máy chủ đã duyệt; vẫn cần đối chiếu hồ sơ quyền sử dụng." }
        "KmsUnapprovedHost" { if ($english) { return "KMS activation points to a host outside the approved list." }; return "Kích hoạt KMS đang trỏ tới máy chủ ngoài danh sách được duyệt." }
        "KmsEntitlementUnverified" { if ($english) { return "KMS activation is present, but licensing entitlement has not been verified." }; return "Có kích hoạt KMS nhưng chưa xác minh được quyền sử dụng." }
        "ActivatedEntitlementUnverified" { if ($english) { return "Activation is present, but licensing entitlement has not been verified." }; return "Đã kích hoạt nhưng chưa xác minh được quyền sử dụng." }
        "Undetermined" { if ($english) { return "Undetermined." }; return "Chưa xác định." }
        default {
            if (-not [string]::IsNullOrWhiteSpace([string]$Fallback)) { return [string]$Fallback }
            if ($english) { return "No conclusion is available." }
            return "Chưa có kết luận."
        }
    }
}

function Format-ToolAssistantReportContext {
    param([AllowNull()][object]$Context, [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN")

    if ($null -eq $Context) {
        if ($Culture -eq "en-US") { return "No current JSON report is available. Run a scan and ask again." }
        return "Chưa có báo cáo JSON hiện tại. Hãy chạy một lượt kiểm tra rồi hỏi lại."
    }
    $windowsConclusion = Get-ToolAssistantLocalizedConclusion -Product Windows -Code ([string]$Context.WindowsConclusionCode) -Fallback ([string]$Context.WindowsConclusion) -Culture $Culture
    $officeConclusion = Get-ToolAssistantLocalizedConclusion -Product Office -Code ([string]$Context.OfficeConclusionCode) -Fallback ([string]$Context.OfficeConclusion) -Culture $Culture
    if ($Culture -eq "en-US") {
        return "Current report summary:`r`n- Windows: $windowsConclusion`r`n- Office: $officeConclusion`r`n- Suspicious findings: $($Context.SuspiciousFindingCount)`r`n- Manual review: $($Context.ManualReviewFindingCount)`r`n- Third-party applications: $($Context.ThirdPartyApplicationCount)"
    }
    return "Tóm tắt báo cáo hiện tại:`r`n- Windows: $windowsConclusion`r`n- Office: $officeConclusion`r`n- Dấu hiệu đáng ngờ: $($Context.SuspiciousFindingCount)`r`n- Cần kiểm tra thủ công: $($Context.ManualReviewFindingCount)`r`n- Phần mềm bên thứ ba: $($Context.ThirdPartyApplicationCount)"
}

function Get-ToolAssistantVariantIndex {
    param([AllowNull()][string]$Text, [ValidateRange(1, 20)][int]$Count)

    $sum = 0
    foreach ($character in ([string]$Text).ToCharArray()) { $sum = ($sum + [int]$character) % 2147483000 }
    return [int]($sum % $Count)
}

function Get-ToolAssistantFallbackAnswer {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Outside','Ambiguous','Insufficient','Unsafe','Missing')][string]$Kind,
        [AllowNull()][string]$Question,
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN"
    )

    $english = [bool]($Culture -eq 'en-US')
    $variants = switch ($Kind) {
        'Unsafe' {
            if ($english) { @(
                'I cannot help bypass licensing or security controls. I can explain the finding and the safe, official remediation path in Tool Kiem Tra.',
                'That would weaken licensing or security controls, so I cannot guide it. I can help review the evidence, back up state, and use an official repair path.'
            ) } else { @(
                'Trợ lý không hướng dẫn lách bản quyền hoặc vô hiệu hóa lớp bảo vệ. Nếu cần, tôi có thể giải thích bằng chứng và hướng khắc phục an toàn, chính thức trong Tool.',
                'Nội dung này có thể làm yếu kiểm soát bản quyền hoặc bảo mật nên Trợ lý không thể hướng dẫn. Tôi có thể hỗ trợ đọc bằng chứng, sao lưu và chọn cách xử lý chính thức.'
            ) }
        }
        'Ambiguous' {
            if ($english) { @(
                'I understand the topic, but the question is still broad. Please name the button, report section, error code, or the result you want explained.',
                'There are several possible meanings here. Add the feature name or exact report/error text so I can answer the right one.'
            ) } else { @(
                'Tôi đã nhận ra chủ đề nhưng câu hỏi còn khá rộng. Bạn hãy thêm tên nút, mục báo cáo, mã lỗi hoặc kết quả cần giải thích để Trợ lý trả lời đúng ý.',
                'Câu này có thể hiểu theo vài hướng. Bạn chỉ cần gửi thêm tên chức năng hoặc nguyên dòng lỗi/kết luận trong báo cáo.'
            ) }
        }
        'Missing' {
            if ($english) { @('The local knowledge base is unavailable, so I cannot give a reliable answer yet.') }
            else { @('Không đọc được bộ tri thức tương thích của phiên bản Tool này nên Trợ lý chưa thể trả lời đáng tin cậy.') }
        }
        'Insufficient' {
            if ($english) { @(
                'This is related to Tool Kiem Tra, but the local data does not contain enough verified detail for a reliable conclusion. Add the exact feature, status, error line, or current report evidence.',
                'I can identify this as a Tool topic, but the available Tool data is not specific enough to answer safely. Send the button name, complete message, or matching report section.'
            ) } else { @(
                'Câu hỏi có liên quan đến Tool, nhưng dữ liệu cục bộ chưa đủ chi tiết đã kiểm chứng để kết luận đáng tin cậy. Bạn hãy thêm tên chức năng, trạng thái, nguyên dòng lỗi hoặc bằng chứng trong báo cáo hiện tại.',
                'Trợ lý nhận ra đây là nội dung của Tool nhưng dữ liệu sẵn có chưa đủ cụ thể để trả lời an toàn. Hãy gửi tên nút, thông báo đầy đủ hoặc đúng mục báo cáo liên quan.'
            ) }
        }
        default {
            $outsideKey = ConvertTo-ToolAssistantSearchKey -Value $Question
            if ($outsideKey -match '\b(?:nau|mon an|bun|pho|com|banh|cong thuc nau)\b') {
                if ($english) { @('Cooking is outside Tool Kiem Tra, so I do not have Tool data to answer that recipe. I can still help with running or interpreting the Tool.') }
                else { @('Câu hỏi về nấu ăn nằm ngoài phạm vi Tool Kiểm Tra nên Trợ lý không có dữ liệu Tool để trả lời công thức này. Trợ lý vẫn có thể hỗ trợ cách chạy hoặc đọc kết quả của Tool.') }
            } elseif ($outsideKey -match '\b(?:thoi tiet|du bao|mua nang|tin tuc|the thao|ty so)\b') {
                if ($english) { @('Live weather, news, and sports are outside Tool Kiem Tra and are not present in its local data. Ask about a Tool status, scan, or report instead.') }
                else { @('Thời tiết, tin tức hoặc tỷ số trực tiếp nằm ngoài phạm vi Tool Kiểm Tra và không có trong dữ liệu cục bộ của Tool. Bạn có thể hỏi về trạng thái, lượt quét hoặc báo cáo của Tool.') }
            } elseif ($outsideKey -match '\b(?:benh|thuoc|suc khoe|bac si|luat|dau tu|chung khoan)\b') {
                if ($english) { @('That professional topic is outside Tool Kiem Tra. This assistant will not substitute Tool data for medical, legal, or financial guidance.') }
                else { @('Chủ đề chuyên môn này nằm ngoài phạm vi Tool Kiểm Tra. Trợ lý không dùng dữ liệu của Tool để thay cho tư vấn y tế, pháp lý hoặc tài chính.') }
            } elseif ($outsideKey -match '\b(?:viet bai|lam tho|dich van ban|ke chuyen|sang tac)\b') {
                if ($english) { @('Writing or translation unrelated to the product is outside Tool Kiem Tra. I can explain Tool text, labels, reports, and workflows when those are the subject.') }
                else { @('Viết bài, làm thơ hoặc dịch nội dung không liên quan đến sản phẩm nằm ngoài phạm vi Tool Kiểm Tra. Nếu đó là nhãn, báo cáo hay quy trình của Tool, Trợ lý có thể giải thích.') }
            } elseif ($english) { @(
                'That topic is outside Tool Kiem Tra, so its local knowledge does not provide an answer. Questions about any Tool feature, state, report, error, or workflow remain in scope.',
                'I cannot connect this question to Tool Kiem Tra data. If it concerns the product, include the screen, button, status, or message so I can use the right Tool context.',
                'This request is unrelated to Tool Kiem Tra. The assistant remains available for the product, its operation, its evidence, and its supported Windows/Office/software workflows.'
            ) } else { @(
                'Chủ đề này không liên quan đến Tool Kiểm Tra nên nằm ngoài phạm vi dữ liệu của Trợ lý. Mọi câu hỏi về sản phẩm, chức năng, trạng thái, báo cáo, lỗi hoặc quy trình của Tool vẫn được hỗ trợ.',
                'Trợ lý chưa liên hệ được câu hỏi này với dữ liệu của Tool Kiểm Tra. Nếu câu hỏi thực sự nói về Tool, bạn hãy thêm tên màn hình, nút, trạng thái hoặc thông báo để xác định đúng ngữ cảnh.',
                'Yêu cầu này không thuộc Tool Kiểm Tra. Trợ lý vẫn trả lời các nội dung liên quan đến cách vận hành, bằng chứng và quy trình Windows, Office hoặc phần mềm mà Tool hỗ trợ.'
            ) }
        }
    }
    $variants = @($variants)
    if ($variants.Count -eq 0) { return '' }
    return [string]$variants[(Get-ToolAssistantVariantIndex -Text $Question -Count $variants.Count)]
}

function Add-ToolAssistantNaturalLead {
    param(
        [Parameter(Mandatory = $true)][string]$Answer,
        [AllowNull()][string]$Question,
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN"
    )

    if ([string]::IsNullOrWhiteSpace($Answer)) { return $Answer }
    # A fixed lead on every turn makes a local knowledge answer sound repetitive.
    # Keep short/direct answers clean and vary the lead only for longer questions.
    $questionText = [string]$Question
    if ($questionText.Trim().Length -lt 42) { return $Answer }
    $leads = if ($Culture -eq 'en-US') {
        @('', 'In short: ', 'The key point is: ', 'For this situation: ')
    } else {
        @('', 'Nói ngắn gọn: ', 'Điểm chính là: ', 'Trong trường hợp này: ')
    }
    return ([string]$leads[(Get-ToolAssistantVariantIndex -Text $Question -Count $leads.Count)] + $Answer)
}

function Get-ToolAssistantAnswer {
    param(
        [Parameter(Mandatory = $true)][string]$Question,
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN",
        [AllowNull()][object]$Knowledge = $null,
        [AllowNull()][object]$ReportContext = $null,
        [AllowNull()][string]$PreviousQuestion = $null,
        [AllowNull()][object]$OnlineMode = $null
    )

    $originalQueryKey = ConvertTo-ToolAssistantSearchKey -Value $Question
    if ([string]::IsNullOrWhiteSpace($originalQueryKey)) {
        if ($Culture -eq "en-US") { return "Please enter a question about Tool Kiem Tra." }
        return "Vui lòng nhập câu hỏi về Tool Kiểm Tra."
    }
    $queryKey = Expand-ToolAssistantContextQuery -QueryKey $originalQueryKey -PreviousQuestion $PreviousQuestion
    if ($queryKey -match '(?:bo qua|vo hieu|tat|lach).*(?:ban quyen|kich hoat|defender|antivirus)|(?:crack|keygen).*(?:cach lam|huong dan|tai o dau)') {
        return Get-ToolAssistantFallbackAnswer -Kind Unsafe -Question $Question -Culture $Culture
    }
    if ($originalQueryKey -match '^(xin chao|chao|hello|hi|alo|hey)\b') {
        if ($Culture -eq "en-US") { return "Hello. I am Tool Assistant. Ask me about a button, report result, error code or workflow in Tool Kiem Tra." }
        return "Xin chào. Đây là Trợ lý Tool. Bạn có thể hỏi về nút chức năng, kết quả báo cáo, mã lỗi hoặc cách dùng Tool Kiểm Tra."
    }
    if ($null -ne $OnlineMode -and $originalQueryKey -match '(?:(?:tool|cong cu|che do|trang thai mang|trang thai).*(?:online|offline).*(?:hien tai|luc nay|bay gio|dang)|(?:trang thai|che do).*(?:online|offline).*(?:hien tai|luc nay|bay gio)|(?:dang|hien tai).*(?:online|offline)|^online hay offline$)') {
        $isOnline = [bool]$OnlineMode
        if ($Culture -eq 'en-US') {
            if ($isOnline) { return 'The Tool is Online for this session. Network access is allowed only for actions you explicitly start; reopening the Tool returns to Offline.' }
            return 'The Tool is currently Offline. Local scans, reports, and the bundled Assistant knowledge remain available without Internet access.'
        }
        if ($isOnline) { return 'Tool đang Online trong phiên hiện tại. Quyền mạng chỉ được dùng cho thao tác bạn chủ động chạy; đóng rồi mở lại Tool sẽ trở về Offline.' }
        return 'Tool hiện đang Offline. Các lượt quét cục bộ, báo cáo và kho tri thức nhúng của Trợ lý vẫn dùng được mà không cần Internet.'
    }
    if ($originalQueryKey -match '(bao cao hien tai|bao cao vua|ket qua hien tai|ket qua vua|trang thai hien tai cua may|may nay dang the nao|scan result|current report|current status|explain (?:the )?current report)') {
        return Format-ToolAssistantReportContext -Context $ReportContext -Culture $Culture
    }
    if ($null -eq $Knowledge) { $Knowledge = Get-ToolAssistantKnowledge }
    if ($null -eq $Knowledge) {
        return Get-ToolAssistantFallbackAnswer -Kind Missing -Question $Question -Culture $Culture
    }
    $toolRelated = Test-ToolAssistantRelatedQuery -QueryKey $originalQueryKey -PreviousQuestion $PreviousQuestion
    $resolved = Resolve-ToolAssistantEntry -QueryKey $queryKey -Knowledge $Knowledge
    $bestEntry = $resolved.Entry
    $contentTokens = @($queryKey -split ' ' | Where-Object { $_.Length -ge 2 -and $_ -notin @('co','la','gi','duoc','khong','the','nao','hay','va') })
    if ($null -eq $bestEntry -or [int]$resolved.Score -lt 14) {
        if ($toolRelated) {
            $documentAnswer = Get-ToolAssistantDocumentAnswer -QueryKey $queryKey -Culture $Culture
            if (-not [string]::IsNullOrWhiteSpace($documentAnswer)) { return Add-ToolAssistantNaturalLead -Answer $documentAnswer -Question $Question -Culture $Culture }
            return Get-ToolAssistantFallbackAnswer -Kind Insufficient -Question $Question -Culture $Culture
        }
        return Get-ToolAssistantFallbackAnswer -Kind Outside -Question $Question -Culture $Culture
    }
    if ([string]$resolved.Route -eq 'ScoredKeywords' -and $contentTokens.Count -le 1) {
        if ($toolRelated) {
            $documentAnswer = Get-ToolAssistantDocumentAnswer -QueryKey $queryKey -Culture $Culture
            if (-not [string]::IsNullOrWhiteSpace($documentAnswer)) { return Add-ToolAssistantNaturalLead -Answer $documentAnswer -Question $Question -Culture $Culture }
            return Get-ToolAssistantFallbackAnswer -Kind Insufficient -Question $Question -Culture $Culture
        }
        return Get-ToolAssistantFallbackAnswer -Kind Outside -Question $Question -Culture $Culture
    }
    if ([string]$resolved.Route -eq 'ScoredKeywords' -and
        $resolved.PSObject.Properties['SecondScore'] -and [int]$resolved.SecondScore -ge 18 -and [int]$resolved.Margin -lt 5) {
        $firstTitle = if ($Culture -eq 'en-US') { [string]$bestEntry.TitleEn } else { [string]$bestEntry.TitleVi }
        $secondTitle = if ($Culture -eq 'en-US') { [string]$resolved.SecondEntry.TitleEn } else { [string]$resolved.SecondEntry.TitleVi }
        $firstAnswer = if ($Culture -eq 'en-US') { [string]$bestEntry.AnswerEn } else { [string]$bestEntry.AnswerVi }
        $secondAnswer = if ($Culture -eq 'en-US') { [string]$resolved.SecondEntry.AnswerEn } else { [string]$resolved.SecondEntry.AnswerVi }
        $combined = "${firstTitle}:`r`n$firstAnswer`r`n`r`n${secondTitle}:`r`n$secondAnswer"
        return Add-ToolAssistantNaturalLead -Answer $combined -Question $Question -Culture $Culture
    }
    $answer = if ($Culture -eq "en-US") { [string]$bestEntry.AnswerEn } else { [string]$bestEntry.AnswerVi }
    if ($queryKey -match '\b(va|dong thoi|kem theo|them nua)\b' -and
        $resolved.PSObject.Properties['SecondEntry'] -and $null -ne $resolved.SecondEntry -and
        [int]$resolved.SecondScore -ge 24 -and [string]$resolved.SecondEntry.Id -ne [string]$bestEntry.Id) {
        $secondAnswer = if ($Culture -eq 'en-US') { [string]$resolved.SecondEntry.AnswerEn } else { [string]$resolved.SecondEntry.AnswerVi }
        $separator = if ($Culture -eq 'en-US') { "`r`n`r`nFor the second part: " } else { "`r`n`r`nVới ý thứ hai: " }
        $answer += $separator + $secondAnswer
    }
    return Add-ToolAssistantNaturalLead -Answer $answer -Question $Question -Culture $Culture
}

function Get-ToolAssistantUiText {
    param([string]$Key, [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN")

    $english = [bool]($Culture -eq "en-US")
    switch ($Key) {
        "Title" { if ($english) { return "Tool Assistant" }; return "Trợ lý Tool" }
        "Scope" { if ($english) { return "Understands all Tool-related questions supported by its local data." }; return "Hiểu mọi câu hỏi liên quan đến Tool theo dữ liệu cục bộ sẵn có." }
        "Offline" { if ($english) { return "OFFLINE · local knowledge" }; return "OFFLINE · tri thức cục bộ" }
        "Online" { if ($english) { return "ONLINE · knowledge sync allowed" }; return "ONLINE · cho phép đồng bộ tri thức" }
        "Input" { if ($english) { return "Ask anything related to Tool Kiem Tra..." }; return "Hỏi mọi nội dung liên quan đến Tool Kiểm Tra..." }
        "Send" { if ($english) { return "Send" }; return "Gửi" }
        "Copy" { if ($english) { return "Copy" }; return "Sao chép" }
        "Clear" { if ($english) { return "Clear" }; return "Xóa hội thoại" }
        "Sync" { if ($english) { return "Sync knowledge" }; return "Đồng bộ tri thức" }
        "ConnectOnline" { if ($english) { return "Connect Online" }; return "Kết nối Online" }
        "OnlineConnected" { if ($english) { return "Online connected" }; return "Đã Online" }
        "ConnectOnlineTip" { if ($english) { return "Allow network access for this session so Tool Assistant can synchronize knowledge. Restarting the tool returns to Offline." }; return "Cho phép mạng trong phiên này để Trợ lý đồng bộ tri thức. Mở lại Tool vẫn trở về Offline." }
        "OnlineConnectedTip" { if ($english) { return "Online is allowed for this session. Use Sync knowledge to download the fixed project knowledge file." }; return "Online đã được cho phép trong phiên này. Dùng Đồng bộ tri thức để tải tệp tri thức cố định của dự án." }
        "SyncTip" { if ($english) { return "Downloads only the Tool Assistant knowledge file; questions and reports are not sent." }; return "Chỉ tải tệp tri thức của Trợ lý; không gửi câu hỏi hoặc báo cáo." }
        "OnlineEnabled" { if ($english) { return "Online is now allowed for this session. You can synchronize Tool Assistant knowledge." }; return "Đã cho phép Online trong phiên này. Bạn có thể đồng bộ tri thức Trợ lý Tool." }
        "OnlineNotEnabled" { if ($english) { return "Online was not enabled. Tool Assistant continues with local knowledge." }; return "Chưa bật Online. Trợ lý tiếp tục dùng tri thức cục bộ." }
        "Close" { if ($english) { return "Close" }; return "Đóng" }
        "Welcome" { if ($english) { return "I understand questions related to Tool Kiem Tra and answer from its local knowledge, documentation, and current report data. Ask in your own words." }; return "Trợ lý hiểu các câu hỏi liên quan đến Tool Kiểm Tra và trả lời từ kho tri thức, tài liệu cùng dữ liệu báo cáo hiện có. Bạn cứ hỏi theo cách tự nhiên." }
        "You" { if ($english) { return "You" }; return "Bạn" }
        "Assistant" { if ($english) { return "Tool Assistant" }; return "Trợ lý Tool" }
        default { return $Key }
    }
}

function Set-ToolAssistantMessageBubbleBounds {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][object]$Wrapper
    )

    $metadata = $Wrapper.Tag
    if ($null -eq $metadata -or $null -eq $metadata.Bubble -or $null -eq $metadata.MessageLabel) { return }
    $chatPadding = $State.Chat.Padding
    $availableWidth = [Math]::Max(180, [int]$State.Chat.ClientSize.Width - $chatPadding.Left - $chatPadding.Right - 20)
    $maximumBubbleWidth = [Math]::Max(200, [Math]::Min(560, [int]($availableWidth * 0.72)))
    $minimumBubbleWidth = [Math]::Min(210, $maximumBubbleWidth)
    $maximumTextWidth = [Math]::Max(160, $maximumBubbleWidth - 20)
    $measureFlags = [Windows.Forms.TextFormatFlags]::WordBreak -bor [Windows.Forms.TextFormatFlags]::TextBoxControl -bor [Windows.Forms.TextFormatFlags]::NoPrefix
    $preferredMessage = [Windows.Forms.TextRenderer]::MeasureText(
        [string]$metadata.MessageLabel.Text,
        $metadata.MessageLabel.Font,
        (New-Object Drawing.Size($maximumTextWidth, 10000)),
        $measureFlags
    )
    $preferredSpeaker = [Windows.Forms.TextRenderer]::MeasureText(
        [string]$metadata.SpeakerLabel.Text,
        $metadata.SpeakerLabel.Font,
        (New-Object Drawing.Size($maximumTextWidth, 40)),
        ([Windows.Forms.TextFormatFlags]::SingleLine -bor [Windows.Forms.TextFormatFlags]::NoPrefix)
    )
    $contentWidth = [Math]::Max($preferredMessage.Width, $preferredSpeaker.Width)
    $bubbleWidth = [Math]::Max($minimumBubbleWidth, [Math]::Min($maximumBubbleWidth, $contentWidth + 20))
    $textWidth = [Math]::Max(160, $bubbleWidth - 20)
    $preferredMessage = [Windows.Forms.TextRenderer]::MeasureText(
        [string]$metadata.MessageLabel.Text,
        $metadata.MessageLabel.Font,
        (New-Object Drawing.Size($textWidth, 10000)),
        $measureFlags
    )
    $messageHeight = [Math]::Max(20, $preferredMessage.Height)
    $metadata.MessageLabel.MaximumSize = New-Object Drawing.Size($textWidth, 0)
    $metadata.Bubble.Size = New-Object Drawing.Size($bubbleWidth, ($messageHeight + 39))
    $metadata.SpeakerLabel.Location = New-Object Drawing.Point(10, 7)
    $metadata.SpeakerLabel.Size = New-Object Drawing.Size($textWidth, 18)
    $metadata.MessageLabel.Location = New-Object Drawing.Point(10, 27)
    $metadata.MessageLabel.Size = New-Object Drawing.Size($textWidth, $messageHeight)
    $Wrapper.Width = $availableWidth
    $Wrapper.Height = $metadata.Bubble.Height + 3
    $metadata.Bubble.Left = if ([string]$metadata.Role -eq 'User') { $availableWidth - $bubbleWidth } else { 0 }
    $metadata.Bubble.Top = 0
    $metadata.Bubble.Invalidate()
}

function Resize-ToolAssistantChatBubbles {
    param([Parameter(Mandatory = $true)][object]$State)

    if ($null -eq $State.Chat) { return }
    foreach ($wrapper in @($State.Chat.Controls)) {
        Set-ToolAssistantMessageBubbleBounds -State $State -Wrapper $wrapper
    }
}

function Complete-ToolAssistantConversationLayout {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [AllowNull()][object]$LatestControl = $null
    )

    $chat = $State.Chat
    if ($null -eq $chat -or $chat.IsDisposed) { return }
    try {
        # Force FlowLayoutPanel to calculate its virtual height before scrolling.
        # The same routine is also called by a one-shot UI timer after the current
        # Click/KeyDown handler returns, which avoids depending on another input.
        $chat.SuspendLayout()
        try { Resize-ToolAssistantChatBubbles -State $State }
        finally { $chat.ResumeLayout($true) }
        $chat.PerformLayout()
        $scrollOffsetY = [Math]::Abs([int]$chat.AutoScrollPosition.Y)
        $contentBottom = [int]$chat.Padding.Top
        foreach ($control in @($chat.Controls)) {
            $virtualBottom = [int]$control.Bottom + $scrollOffsetY + [int]$control.Margin.Bottom
            $contentBottom = [Math]::Max($contentBottom, $virtualBottom)
        }
        $chat.AutoScrollMinSize = New-Object Drawing.Size(0, ($contentBottom + [int]$chat.Padding.Bottom))
        $chat.PerformLayout()
        if ($null -ne $LatestControl -and -not $LatestControl.IsDisposed) {
            if (-not $LatestControl.IsHandleCreated) { [void]$LatestControl.CreateControl() }
            $chat.ScrollControlIntoView($LatestControl)
        }
        $targetY = [Math]::Max(0, $contentBottom - [int]$chat.ClientSize.Height + [int]$chat.Padding.Bottom + 4)
        $chat.AutoScrollPosition = New-Object Drawing.Point(0, $targetY)
        $chat.Invalidate($true)
        $chat.Update()

        if ($chat.IsHandleCreated) {
            # IsSubmitting remains true while DoEvents runs, so Send/Enter cannot
            # re-enter the answer pipeline while the current response is painted.
            [Windows.Forms.Application]::DoEvents()
            $chat.PerformLayout()
            if ($null -ne $LatestControl -and -not $LatestControl.IsDisposed) {
                $chat.ScrollControlIntoView($LatestControl)
            }
            $chat.AutoScrollPosition = New-Object Drawing.Point(0, $targetY)
            try {
                if ($chat.VerticalScroll.Visible) {
                    $maximumValue = [Math]::Max($chat.VerticalScroll.Minimum, $chat.VerticalScroll.Maximum - $chat.VerticalScroll.LargeChange + 1)
                    $chat.VerticalScroll.Value = $maximumValue
                }
            } catch {}
            $chat.Update()
        }
    } catch {
        # Rendering recovery must not discard an answer that was already produced.
    }
}

function Update-ToolAssistantConversationUi {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [AllowNull()][object]$LatestControl = $null
    )

    Complete-ToolAssistantConversationLayout -State $State -LatestControl $LatestControl

    # WinForms may postpone FlowLayoutPanel scrolling until the event handler has
    # returned. Restart a one-shot UI timer so the newest answer is laid out and
    # painted on the next message-pump turn without waiting for another question.
    if ($State.PSObject.Properties['PendingRevealControl']) { $State.PendingRevealControl = $LatestControl }
    if (-not $State.PSObject.Properties['RevealQueued']) {
        $State | Add-Member -NotePropertyName RevealQueued -NotePropertyValue $false
    }
    if (-not [bool]$State.RevealQueued -and $State.Chat.IsHandleCreated) {
        $State.RevealQueued = $true
        $queuedState = $State
        $revealCallback = [Action]{
            try {
                $queuedState.RevealQueued = $false
                $latest = $queuedState.PendingRevealControl
                $queuedState.PendingRevealControl = $null
                Complete-ToolAssistantConversationLayout -State $queuedState -LatestControl $latest
            } catch {
                $queuedState.RevealQueued = $false
            }
        }.GetNewClosure()
        try { [void]$State.Chat.BeginInvoke($revealCallback) }
        catch { $State.RevealQueued = $false }
    }
    if ($State.PSObject.Properties['RenderTimer'] -and $null -ne $State.RenderTimer) {
        try {
            $State.RenderTimer.Stop()
            $State.RenderTimer.Start()
        } catch [ObjectDisposedException] {
            # The assistant window is already closing; there is nothing left to repaint.
        }
    }
}

function Add-ToolAssistantChatMessage {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [Parameter(Mandatory = $true)][ValidateSet('User','Assistant')][string]$Role,
        [AllowEmptyString()][string]$Message = ""
    )

    $chat = $State.Chat
    if ($null -eq $chat) { return $null }
    $speaker = Get-ToolAssistantUiText $(if ($Role -eq 'User') { 'You' } else { 'Assistant' }) $State.Culture
    if ($State.PSObject.Properties['Transcript'] -and $null -ne $State.Transcript) {
        if ($State.Transcript.Length -gt 0) { [void]$State.Transcript.Append("`r`n`r`n") }
        [void]$State.Transcript.Append($speaker).Append("`r`n").Append([string]$Message)
    }

    $chat.SuspendLayout()
    $wrapper = New-Object Windows.Forms.Panel
    $wrapper.BackColor = $chat.BackColor
    $wrapper.Margin = New-Object Windows.Forms.Padding(0, 0, 0, 9)
    $bubble = New-Object Windows.Forms.Panel
    $bubble.BorderStyle = 'None'
    $bubble.BackColor = if ($Role -eq 'User') { $State.UserBubbleColor } else { $State.AssistantBubbleColor }
    $bubble.Tag = if ($Role -eq 'User') { $State.UserBubbleBorderColor } else { $State.AssistantBubbleBorderColor }
    $bubble.Add_Paint({
        param($sender, $eventArgs)
        if ($sender.ClientSize.Width -le 1 -or $sender.ClientSize.Height -le 1) { return }
        $pen = New-Object Drawing.Pen([Drawing.Color]$sender.Tag, 1)
        try { $eventArgs.Graphics.DrawRectangle($pen, 0, 0, $sender.ClientSize.Width - 1, $sender.ClientSize.Height - 1) }
        finally { $pen.Dispose() }
    })
    $speakerLabel = New-Object Windows.Forms.Label
    $speakerLabel.Text = $speaker
    $speakerLabel.Font = $State.SpeakerFont
    $speakerLabel.ForeColor = if ($Role -eq 'User') { $State.UserTextColor } else { $State.AssistantHeaderColor }
    $speakerLabel.BackColor = [Drawing.Color]::Transparent
    $speakerLabel.Location = New-Object Drawing.Point(10, 7)
    $messageLabel = New-Object Windows.Forms.Label
    $messageLabel.Text = [string]$Message
    $messageLabel.Font = $State.MessageFont
    $messageLabel.ForeColor = if ($Role -eq 'User') { $State.UserTextColor } else { $State.AssistantTextColor }
    $messageLabel.BackColor = [Drawing.Color]::Transparent
    $messageLabel.Location = New-Object Drawing.Point(10, 27)
    $messageLabel.AutoEllipsis = $false
    $messageLabel.UseCompatibleTextRendering = $false
    $bubble.Controls.Add($speakerLabel)
    $bubble.Controls.Add($messageLabel)
    $wrapper.Controls.Add($bubble)
    $wrapper.Tag = [pscustomobject]@{
        Role = $Role
        Bubble = $bubble
        SpeakerLabel = $speakerLabel
        MessageLabel = $messageLabel
    }
    Set-ToolAssistantMessageBubbleBounds -State $State -Wrapper $wrapper
    [void]$chat.Controls.Add($wrapper)
    $chat.ResumeLayout($true)
    Update-ToolAssistantConversationUi -State $State -LatestControl $wrapper
    return $wrapper
}

function Clear-ToolAssistantConversation {
    param([Parameter(Mandatory = $true)][object]$State)

    foreach ($control in @($State.Chat.Controls)) {
        $State.Chat.Controls.Remove($control)
        $control.Dispose()
    }
    if ($State.PSObject.Properties['Transcript'] -and $null -ne $State.Transcript) { [void]$State.Transcript.Clear() }
    if ($State.PSObject.Properties['LastQuestionKey']) { $State.LastQuestionKey = "" }
    if ($State.PSObject.Properties['LastQuestionText']) { $State.LastQuestionText = "" }
    if ($State.PSObject.Properties['LastAnswer']) { $State.LastAnswer = "" }
}

function Invoke-ToolAssistantQuestion {
    param([Parameter(Mandatory = $true)][object]$State)

    if ($State.PSObject.Properties['IsSubmitting'] -and [bool]$State.IsSubmitting) { return "" }
    $question = [string]$State.Input.Text
    if ([string]::IsNullOrWhiteSpace($question)) { return "" }
    $question = $question.Trim()
    $answer = ""
    $questionKey = ConvertTo-ToolAssistantSearchKey -Value $question
    $previousQuestion = if ($State.PSObject.Properties['LastQuestionText']) { [string]$State.LastQuestionText } else { '' }
    $State.IsSubmitting = $true
    if ($State.PSObject.Properties['SendButton'] -and $null -ne $State.SendButton) { $State.SendButton.Enabled = $false }
    $State.Input.Enabled = $false
    try {
        $State.Input.Clear()
        [void](Add-ToolAssistantChatMessage -State $State -Role User -Message $question)
        if ($State.PSObject.Properties['LastQuestionKey'] -and
            -not [string]::IsNullOrWhiteSpace([string]$State.LastQuestionKey) -and
            [string]$State.LastQuestionKey -eq $questionKey) {
            $answer = if ($State.Culture -eq 'en-US') {
                "This is the same question as the previous turn. The answer above is still current; add the exact error, report line, or a different detail if you want me to go deeper."
            } else {
                "Câu này trùng với lượt ngay trước. Nội dung phía trên vẫn còn hiệu lực; bạn hãy thêm mã lỗi, dòng báo cáo hoặc chi tiết khác nếu muốn Trợ lý phân tích sâu hơn."
            }
        } else {
            $currentOnlineMode = if ($State.PSObject.Properties['OnlineMode']) { [bool]$State.OnlineMode } else { $null }
            $answer = Get-ToolAssistantAnswer -Question $question -Culture $State.Culture -Knowledge $State.Knowledge -ReportContext $State.ReportContext -PreviousQuestion $previousQuestion -OnlineMode $currentOnlineMode
        }
        [void](Add-ToolAssistantChatMessage -State $State -Role Assistant -Message $answer)
        if ($State.PSObject.Properties['LastQuestionKey']) { $State.LastQuestionKey = $questionKey }
        if ($State.PSObject.Properties['LastQuestionText']) { $State.LastQuestionText = $question }
        if ($State.PSObject.Properties['LastAnswer']) { $State.LastAnswer = [string]$answer }
    } finally {
        $State.IsSubmitting = $false
        $State.Input.Enabled = $true
        if ($State.PSObject.Properties['SendButton'] -and $null -ne $State.SendButton) { $State.SendButton.Enabled = $true }
        $State.Input.Focus()
    }
    return [string]$answer
}

function Queue-ToolAssistantQuestion {
    param([Parameter(Mandatory = $true)][object]$State)

    if ([bool]$State.IsSubmitting -or
        ($State.PSObject.Properties['SubmissionQueued'] -and [bool]$State.SubmissionQueued) -or
        [string]::IsNullOrWhiteSpace([string]$State.Input.Text)) { return }
    if (-not $State.PSObject.Properties['Window'] -or $null -eq $State.Window -or $State.Window.IsDisposed) {
        [void](Invoke-ToolAssistantQuestion -State $State)
        return
    }
    $State.SubmissionQueued = $true
    $State.SendButton.Enabled = $false
    $State.Input.Enabled = $false
    $callbackScript = {
        try {
            $State.SubmissionQueued = $false
            $State.Input.Enabled = $true
            $State.SendButton.Enabled = $true
            [void](Invoke-ToolAssistantQuestion -State $State)
        } catch {
            $State.SubmissionQueued = $false
            $State.Input.Enabled = $true
            $State.SendButton.Enabled = $true
        }
    }.GetNewClosure()
    $callback = [Action]$callbackScript
    try { [void]$State.Window.BeginInvoke($callback) }
    catch {
        $State.SubmissionQueued = $false
        $State.Input.Enabled = $true
        $State.SendButton.Enabled = $true
    }
}

function Update-ToolAssistantConnectionUi {
    param([Parameter(Mandatory = $true)][object]$State)

    $online = [bool]$State.OnlineMode
    $State.ModeLabel.Text = Get-ToolAssistantUiText $(if ($online) { "Online" } else { "Offline" }) $State.Culture
    $State.ModeLabel.ForeColor = if ($online) { $State.OnlineColor } else { $State.OfflineColor }
    if ($State.PSObject.Properties['OnlineBadgeBackColor'] -and $State.PSObject.Properties['OfflineBadgeBackColor']) {
        $State.ModeLabel.BackColor = if ($online) { $State.OnlineBadgeBackColor } else { $State.OfflineBadgeBackColor }
    }
    $State.OnlineButton.Text = Get-ToolAssistantUiText $(if ($online) { "OnlineConnected" } else { "ConnectOnline" }) $State.Culture
    if ($State.PSObject.Properties['ToolTip'] -and $null -ne $State.ToolTip) {
        $State.ToolTip.SetToolTip($State.ModeLabel, [string]$State.ModeLabel.Text)
    }
    $State.OnlineButton.Enabled = -not $online
    $State.SyncButton.Enabled = $online
    $State.ToolTip.SetToolTip($State.OnlineButton, (Get-ToolAssistantUiText $(if ($online) { "OnlineConnectedTip" } else { "ConnectOnlineTip" }) $State.Culture))
    $State.ToolTip.SetToolTip($State.SyncButton, (Get-ToolAssistantUiText "SyncTip" $State.Culture))
}

function Set-ToolAssistantHeaderBounds {
    param(
        [Parameter(Mandatory = $true)][object]$Header,
        [Parameter(Mandatory = $true)][object]$TitleLabel,
        [Parameter(Mandatory = $true)][object]$ScopeLabel,
        [Parameter(Mandatory = $true)][object]$ModeLabel
    )

    $clientWidth = [int]$Header.ClientSize.Width
    if ($clientWidth -le 0) { return }
    $rightMargin = 18
    $modeWidth = [Math]::Min(272, [Math]::Max(220, [int]($clientWidth * 0.36)))
    $ModeLabel.Size = New-Object Drawing.Size($modeWidth, 32)
    $ModeLabel.Location = New-Object Drawing.Point([Math]::Max(390, $clientWidth - $modeWidth - $rightMargin), 14)
    $leftContentRight = [Math]::Max(250, [int]$ModeLabel.Left - 14)
    $TitleLabel.Width = [Math]::Max(220, $leftContentRight - [int]$TitleLabel.Left)
    $ScopeLabel.Width = [Math]::Max(220, $leftContentRight - [int]$ScopeLabel.Left)
}

function Set-ToolAssistantInputFrameState {
    param(
        [Parameter(Mandatory = $true)][object]$State,
        [bool]$Focused
    )

    if (-not $State.PSObject.Properties['InputFrame'] -or $null -eq $State.InputFrame -or $State.InputFrame.IsDisposed) { return }
    $State.InputFrame.BackColor = if ($Focused) { $State.InputFocusBorderColor } else { $State.InputIdleBorderColor }
    $State.InputFrame.Invalidate($true)
}

function Enable-ToolAssistantOnline {
    param([Parameter(Mandatory = $true)][object]$State)

    if ([bool]$State.OnlineMode) { return $true }
    $allowed = $false
    if ($State.RequestOnline -is [scriptblock]) {
        try { $allowed = [bool](& $State.RequestOnline) } catch { $allowed = $false }
    }
    if ($allowed) {
        $State.OnlineMode = $true
        Update-ToolAssistantConnectionUi -State $State
        [void](Add-ToolAssistantChatMessage -State $State -Role Assistant -Message (Get-ToolAssistantUiText "OnlineEnabled" $State.Culture))
        return $true
    }
    [void](Add-ToolAssistantChatMessage -State $State -Role Assistant -Message (Get-ToolAssistantUiText "OnlineNotEnabled" $State.Culture))
    return $false
}

function Show-ToolAssistantWindow {
    param(
        [AllowNull()][object]$Owner,
        [ValidateSet("vi-VN", "en-US")][string]$Culture = "vi-VN",
        [bool]$OnlineMode = $false,
        [AllowNull()][string]$CurrentReportPath = "",
        [ValidateSet("Light", "Dark")][string]$Theme = "Light",
        [AllowNull()][scriptblock]$RequestOnline = $null
    )

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $knowledge = Get-ToolAssistantKnowledge
    $reportContext = Get-ToolAssistantReportContext -ReportPath $CurrentReportPath
    $dark = [bool]($Theme -eq "Dark")
    $background = if ($dark) { [Drawing.Color]::FromArgb(17, 22, 30) } else { [Drawing.Color]::FromArgb(244, 247, 251) }
    $surface = if ($dark) { [Drawing.Color]::FromArgb(29, 36, 48) } else { [Drawing.Color]::White }
    $text = if ($dark) { [Drawing.Color]::FromArgb(229, 234, 242) } else { [Drawing.Color]::FromArgb(37, 48, 66) }
    $muted = if ($dark) { [Drawing.Color]::FromArgb(166, 177, 194) } else { [Drawing.Color]::FromArgb(102, 112, 133) }
    $primary = if ($dark) { [Drawing.Color]::FromArgb(137, 190, 255) } else { [Drawing.Color]::FromArgb(0, 98, 218) }
    $onlineColor = if ($dark) { [Drawing.Color]::FromArgb(255, 196, 104) } else { [Drawing.Color]::FromArgb(140, 78, 0) }
    $offlineColor = if ($dark) { [Drawing.Color]::FromArgb(128, 226, 174) } else { [Drawing.Color]::FromArgb(14, 112, 70) }
    $onlineBadgeBackColor = if ($dark) { [Drawing.Color]::FromArgb(67, 45, 19) } else { [Drawing.Color]::FromArgb(255, 243, 219) }
    $offlineBadgeBackColor = if ($dark) { [Drawing.Color]::FromArgb(24, 63, 49) } else { [Drawing.Color]::FromArgb(226, 247, 238) }
    $inputSurface = if ($dark) { [Drawing.Color]::FromArgb(22, 29, 40) } else { [Drawing.Color]::FromArgb(250, 252, 255) }
    $inputIdleBorder = if ($dark) { [Drawing.Color]::FromArgb(94, 111, 137) } else { [Drawing.Color]::FromArgb(118, 136, 162) }

    $dialog = New-Object Windows.Forms.Form
    $dialog.Text = Get-ToolAssistantUiText "Title" $Culture
    $dialog.StartPosition = "CenterParent"
    $dialog.Size = New-Object Drawing.Size(820, 620)
    $dialog.MinimumSize = New-Object Drawing.Size(680, 500)
    $dialog.AutoScaleMode = [Windows.Forms.AutoScaleMode]::Dpi
    $dialog.BackColor = $background
    $dialog.Font = New-Object Drawing.Font("Segoe UI", 9)
    $assistantToolTip = New-Object Windows.Forms.ToolTip
    $assistantToolTip.AutoPopDelay = 12000
    $assistantToolTip.InitialDelay = 350
    $assistantToolTip.ReshowDelay = 100

    # A row-based host prevents the Fill chat area from extending underneath the
    # bottom composer. The previous Dock/z-order layout could hide the newest
    # message until another input forced a layout pass.
    $assistantLayout = New-Object Windows.Forms.TableLayoutPanel
    $assistantLayout.Dock = 'Fill'
    $assistantLayout.ColumnCount = 1
    $assistantLayout.RowCount = 4
    $assistantLayout.Margin = New-Object Windows.Forms.Padding(0)
    $assistantLayout.Padding = New-Object Windows.Forms.Padding(0)
    [void]$assistantLayout.ColumnStyles.Add((New-Object Windows.Forms.ColumnStyle([Windows.Forms.SizeType]::Percent, 100)))
    [void]$assistantLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 72)))
    [void]$assistantLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 42)))
    [void]$assistantLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Percent, 100)))
    [void]$assistantLayout.RowStyles.Add((New-Object Windows.Forms.RowStyle([Windows.Forms.SizeType]::Absolute, 114)))
    $dialog.Controls.Add($assistantLayout)

    $header = New-Object Windows.Forms.Panel
    $header.Dock = "Fill"
    $header.Margin = New-Object Windows.Forms.Padding(0)
    $header.BackColor = $surface
    $assistantLayout.Controls.Add($header, 0, 0)
    $title = New-Object Windows.Forms.Label
    $title.Text = Get-ToolAssistantUiText "Title" $Culture
    $title.Font = New-Object Drawing.Font("Segoe UI Semibold", 17)
    $title.ForeColor = $primary
    $title.Location = New-Object Drawing.Point(18, 10)
    $title.Size = New-Object Drawing.Size(460, 32)
    $header.Controls.Add($title)
    $scope = New-Object Windows.Forms.Label
    $scope.Text = Get-ToolAssistantUiText "Scope" $Culture
    $scope.ForeColor = $muted
    $scope.Location = New-Object Drawing.Point(20, 43)
    $scope.Size = New-Object Drawing.Size(570, 22)
    $scope.AutoEllipsis = $true
    $header.Controls.Add($scope)
    $mode = New-Object Windows.Forms.Label
    $mode.TextAlign = "MiddleCenter"
    $mode.AutoEllipsis = $true
    $mode.Anchor = "Top,Right"
    $mode.Font = New-Object Drawing.Font("Segoe UI Semibold", 9)
    $mode.Padding = New-Object Windows.Forms.Padding(10, 0, 10, 0)
    $mode.BorderStyle = 'FixedSingle'
    $mode.Location = New-Object Drawing.Point(510, 14)
    $mode.Size = New-Object Drawing.Size(272, 32)
    $header.Controls.Add($mode)
    $headerLayout = {
        param($sender, $eventArgs)
        Set-ToolAssistantHeaderBounds -Header $sender -TitleLabel $title -ScopeLabel $scope -ModeLabel $mode
    }.GetNewClosure()
    $header.Add_SizeChanged($headerLayout)

    $suggestions = New-Object Windows.Forms.FlowLayoutPanel
    $suggestions.Dock = "Fill"
    $suggestions.Margin = New-Object Windows.Forms.Padding(0)
    $suggestions.Padding = New-Object Windows.Forms.Padding(12, 5, 8, 3)
    $suggestions.WrapContents = $false
    $suggestions.AutoScroll = $true
    $suggestions.BackColor = $background
    $assistantLayout.Controls.Add($suggestions, 0, 1)

    $chat = New-Object Windows.Forms.FlowLayoutPanel
    $chat.Dock = "Fill"
    $chat.Margin = New-Object Windows.Forms.Padding(10, 4, 10, 4)
    $chat.BorderStyle = "FixedSingle"
    $chat.BackColor = $background
    $chat.FlowDirection = [Windows.Forms.FlowDirection]::TopDown
    $chat.WrapContents = $false
    $chat.AutoScroll = $true
    $chat.Padding = New-Object Windows.Forms.Padding(10, 9, 6, 9)
    $assistantLayout.Controls.Add($chat, 0, 2)

    $composer = New-Object Windows.Forms.Panel
    $composer.Dock = "Fill"
    $composer.Margin = New-Object Windows.Forms.Padding(0)
    $composer.BackColor = $surface
    $assistantLayout.Controls.Add($composer, 0, 3)
    $inputFrame = New-Object Windows.Forms.Panel
    $inputFrame.Anchor = "Top,Left,Right"
    $inputFrame.Location = New-Object Drawing.Point(14, 10)
    $inputFrame.Size = New-Object Drawing.Size(650, 54)
    $inputFrame.BackColor = $inputIdleBorder
    $composer.Controls.Add($inputFrame)
    $input = New-Object Windows.Forms.TextBox
    $input.Multiline = $true
    $input.AcceptsReturn = $true
    $input.ScrollBars = "Vertical"
    $input.ForeColor = $text
    $input.BackColor = $inputSurface
    $input.BorderStyle = 'None'
    $input.Anchor = "Top,Left,Right,Bottom"
    $input.Location = New-Object Drawing.Point(7, 6)
    $input.Size = New-Object Drawing.Size(636, 42)
    $input.Tag = Get-ToolAssistantUiText "Input" $Culture
    $inputFrame.Controls.Add($input)
    $send = New-Object Windows.Forms.Button
    $send.Text = Get-ToolAssistantUiText "Send" $Culture
    $send.Anchor = "Top,Right"
    $send.Location = New-Object Drawing.Point(676, 10)
    $send.Size = New-Object Drawing.Size(126, 54)
    $send.BackColor = $primary
    $send.ForeColor = [Drawing.Color]::White
    $send.FlatStyle = "Flat"
    $send.FlatAppearance.BorderSize = 0
    $composer.Controls.Add($send)
    $copy = New-Object Windows.Forms.Button
    $copy.Text = Get-ToolAssistantUiText "Copy" $Culture
    $copy.Location = New-Object Drawing.Point(14, 72)
    $copy.Size = New-Object Drawing.Size(112, 30)
    $composer.Controls.Add($copy)
    $clear = New-Object Windows.Forms.Button
    $clear.Text = Get-ToolAssistantUiText "Clear" $Culture
    $clear.Location = New-Object Drawing.Point(134, 72)
    $clear.Size = New-Object Drawing.Size(134, 30)
    $composer.Controls.Add($clear)
    $sync = New-Object Windows.Forms.Button
    $sync.Text = Get-ToolAssistantUiText "Sync" $Culture
    $sync.Location = New-Object Drawing.Point(276, 72)
    $sync.Size = New-Object Drawing.Size(142, 30)
    $composer.Controls.Add($sync)
    $online = New-Object Windows.Forms.Button
    $online.Location = New-Object Drawing.Point(426, 72)
    $online.Size = New-Object Drawing.Size(128, 30)
    $online.FlatStyle = "Flat"
    $online.FlatAppearance.BorderSize = 1
    $online.ForeColor = $primary
    $online.BackColor = $surface
    $composer.Controls.Add($online)
    $close = New-Object Windows.Forms.Button
    $close.Text = Get-ToolAssistantUiText "Close" $Culture
    $close.Anchor = "Bottom,Right"
    $close.Location = New-Object Drawing.Point(684, 72)
    $close.Size = New-Object Drawing.Size(118, 30)
    $composer.Controls.Add($close)

    $composerLayout = {
        param($sender, $eventArgs)
        $clientWidth = [int]$sender.ClientSize.Width
        if ($clientWidth -le 0) { return }
        $send.Left = [Math]::Max(228, $clientWidth - $send.Width - 14)
        $inputFrame.Width = [Math]::Max(190, $send.Left - $inputFrame.Left - 10)
        $input.Width = [Math]::Max(176, [int]$inputFrame.ClientSize.Width - 14)
        $input.Height = [Math]::Max(36, [int]$inputFrame.ClientSize.Height - 12)
        $close.Left = [Math]::Max(562, $clientWidth - $close.Width - 14)
    }.GetNewClosure()
    $composer.Add_SizeChanged($composerLayout)

    $speakerFont = New-Object Drawing.Font("Segoe UI Semibold", 9)
    $messageFont = New-Object Drawing.Font("Segoe UI", 10)
    $assistantState = [pscustomobject]@{
        Window = $dialog
        LayoutRoot = $assistantLayout
        Composer = $composer
        Input = $input
        InputFrame = $inputFrame
        Chat = $chat
        SendButton = $send
        Culture = $Culture
        Knowledge = $knowledge
        ReportContext = $reportContext
        OnlineMode = [bool]$OnlineMode
        RequestOnline = $RequestOnline
        ModeLabel = $mode
        OnlineButton = $online
        SyncButton = $sync
        ToolTip = $assistantToolTip
        PrimaryColor = $primary
        TextColor = $text
        OnlineColor = $onlineColor
        OfflineColor = $offlineColor
        OnlineBadgeBackColor = $onlineBadgeBackColor
        OfflineBadgeBackColor = $offlineBadgeBackColor
        InputIdleBorderColor = $inputIdleBorder
        InputFocusBorderColor = $primary
        SpeakerFont = $speakerFont
        MessageFont = $messageFont
        Transcript = New-Object Text.StringBuilder
        IsSubmitting = $false
        SubmissionQueued = $false
        LastQuestionKey = ""
        LastQuestionText = ""
        LastAnswer = ""
        PendingRevealControl = $null
        RevealQueued = $false
        RenderTimer = $null
        UserBubbleColor = $(if ($dark) { [Drawing.Color]::FromArgb(35, 105, 190) } else { [Drawing.Color]::FromArgb(0, 98, 218) })
        UserBubbleBorderColor = $(if ($dark) { [Drawing.Color]::FromArgb(151, 204, 255) } else { [Drawing.Color]::FromArgb(0, 72, 164) })
        UserTextColor = [Drawing.Color]::White
        AssistantBubbleColor = $(if ($dark) { [Drawing.Color]::FromArgb(38, 47, 61) } else { [Drawing.Color]::FromArgb(232, 241, 252) })
        AssistantBubbleBorderColor = $(if ($dark) { [Drawing.Color]::FromArgb(83, 106, 139) } else { [Drawing.Color]::FromArgb(143, 174, 211) })
        AssistantTextColor = $text
        AssistantHeaderColor = $primary
    }
    $renderTimer = New-Object Windows.Forms.Timer
    $renderTimer.Interval = 25
    $renderTimer.Tag = $assistantState
    $renderTimer.Add_Tick({
        param($sender, $eventArgs)
        $sender.Stop()
        $state = $sender.Tag
        if ($null -eq $state -or $null -eq $state.Chat -or $state.Chat.IsDisposed) { return }
        $latest = $state.PendingRevealControl
        $state.PendingRevealControl = $null
        Complete-ToolAssistantConversationLayout -State $state -LatestControl $latest
    })
    $assistantState.RenderTimer = $renderTimer
    $chat.Tag = $assistantState
    $chat.Add_SizeChanged({ param($sender, $eventArgs); Resize-ToolAssistantChatBubbles -State $sender.Tag })
    Update-ToolAssistantConnectionUi -State $assistantState
    [void](Add-ToolAssistantChatMessage -State $assistantState -Role Assistant -Message (Get-ToolAssistantUiText "Welcome" $Culture))

    $send.Tag = $assistantState
    $send.Add_Click({
        param($sender, $eventArgs)
        Queue-ToolAssistantQuestion -State $sender.Tag
    })
    $input.Tag = $assistantState
    $input.Add_Enter({ param($sender, $eventArgs); Set-ToolAssistantInputFrameState -State $sender.Tag -Focused $true })
    $input.Add_Leave({ param($sender, $eventArgs); Set-ToolAssistantInputFrameState -State $sender.Tag -Focused $false })
    $input.Add_KeyDown({
        param($sender, $eventArgs)
        if ($eventArgs.KeyCode -eq [Windows.Forms.Keys]::Enter -and -not $eventArgs.Shift) {
            $eventArgs.SuppressKeyPress = $true
            $eventArgs.Handled = $true
            Queue-ToolAssistantQuestion -State $sender.Tag
        }
    })
    $copy.Tag = $assistantState
    $copy.Add_Click({
        param($sender, $eventArgs)
        if ($sender.Tag.Transcript.Length -gt 0) { [Windows.Forms.Clipboard]::SetText($sender.Tag.Transcript.ToString()) }
    })
    $clear.Tag = $assistantState
    $clear.Add_Click({
        param($sender, $eventArgs)
        Clear-ToolAssistantConversation -State $sender.Tag
        [void](Add-ToolAssistantChatMessage -State $sender.Tag -Role Assistant -Message (Get-ToolAssistantUiText "Welcome" $sender.Tag.Culture))
    })
    $sync.Tag = $assistantState
    $sync.Add_Click({
        param($sender, $eventArgs)
        $state = $sender.Tag
        $result = Sync-ToolAssistantKnowledge -OnlineMode ([bool]$state.OnlineMode) -Culture ([string]$state.Culture)
        if ($result.Success) { $state.Knowledge = Get-ToolAssistantKnowledge }
        [void](Add-ToolAssistantChatMessage -State $state -Role Assistant -Message ([string]$result.Message))
    })
    $online.Tag = $assistantState
    $online.Add_Click({
        param($sender, $eventArgs)
        [void](Enable-ToolAssistantOnline -State $sender.Tag)
    })
    $close.Tag = $dialog
    $close.Add_Click({ param($sender, $eventArgs); $sender.Tag.Close() })
    $dialog.CancelButton = $close

    $suggestedQuestions = if ($Culture -eq "en-US") {
        @("What does Undetermined mean?", "How does Offline mode work?", "Explain the current report")
    } else {
        @("CHƯA XÁC ĐỊNH nghĩa là gì?", "Chế độ Offline hoạt động thế nào?", "Giải thích báo cáo hiện tại")
    }
    foreach ($question in $suggestedQuestions) {
        $suggestion = New-Object Windows.Forms.Button
        $suggestion.Text = $question
        $suggestion.AutoSize = $true
        $suggestion.Height = 28
        $suggestion.FlatStyle = "Flat"
        $suggestion.ForeColor = $primary
        $suggestion.BackColor = $surface
        $suggestion.Tag = [pscustomobject]@{ State=$assistantState; Question=$question }
        $suggestion.Add_Click({
            param($sender, $eventArgs)
            $state = $sender.Tag.State
            $state.Input.Text = [string]$sender.Tag.Question
            $state.Input.Focus()
            $state.Input.SelectionStart = $state.Input.TextLength
        })
        [void]$suggestions.Controls.Add($suggestion)
    }
    $dialog.Add_Shown({
        $assistantLayout.PerformLayout()
        Set-ToolAssistantHeaderBounds -Header $header -TitleLabel $title -ScopeLabel $scope -ModeLabel $mode
        $composerLayout.Invoke($composer, [EventArgs]::Empty)
        Set-ToolAssistantInputFrameState -State $assistantState -Focused $true
        Complete-ToolAssistantConversationLayout -State $assistantState -LatestControl $assistantState.PendingRevealControl
        $input.Focus()
    }.GetNewClosure())
    if ($Owner) { [void]$dialog.ShowDialog($Owner) } else { [void]$dialog.ShowDialog() }
    $renderTimer.Stop()
    $renderTimer.Dispose()
    $assistantToolTip.Dispose()
    $speakerFont.Dispose()
    $messageFont.Dispose()
    $dialog.Dispose()
}
