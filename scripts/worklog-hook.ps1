# Claude Codeのhookとして、AIの作業区間（ユーザーの返事待ちを除く）を記録し、
# タスク毎引継ぎ資料（引継ぎ資料/タスク毎/<バックログ名称>_<タスク名>_引継書.md）が
# Writeツール・Editツールで保存された時に、その「## 作業ログ」へ書き込む。
#
# 背景：
# - 引継書ルール「作業時間の計測」では、作業ログの開始・終了時刻をAIが記載するが、
#   AIの記載では、形式の誤り（日付のみ・「頃」等）や開始時刻の抜けが起きる。
#   hookで記録することで、AIの記載に頼らずに作業ログを残す。
#
# 動作（hookの種類ごと。hookの登録はsetup-worklog-hooks.ps1で行う）：
# - UserPromptSubmit（ユーザーの発言時）：作業区間を開始する。
# - PreToolUse（AskUserQuestionの直前）：作業区間を終了する（回答待ちを除くため）。
# - PostToolUse・PostToolUseFailure（AskUserQuestionの後）：作業区間を開始する。
# - Stop（AIの応答の終了時）：作業区間を終了する。
# - PostToolUse（Write・Editの後）：保存したファイルがタスク毎引継ぎ資料であれば、
#   前回の書き込み以降に記録した作業区間を「## 作業ログ」へ書き込む。
# - 作業区間の開始は分単位で切り捨て、終了は切り上げる（終了は開始より1分以上後にする）。
#   分単位で重なる・接する区間（直前の作業ログの行を含む）は1行にまとめる。
# - 「## 作業ログ」の中のテンプレートの記載例（<...>の行）は、書き込み時に削除する。
#   「## 作業ログ」がなければ、ファイルの末尾に追加する。
# - 記録途中の作業区間は、セッションごとに一時フォルダ（%TEMP%\hojou-worklog\）へ保存する。
#   30日以上更新のないものは削除する。
#
# 限界（必ず確認すること）：
# - 権限確認（ツール実行の許可）の待ち時間は、作業区間から除けない。
# - ユーザーが応答を中断した場合（Stopが起きない）、その作業区間の終了は、最後にこのhookが
#   動いた時刻（AskUserQuestion・Write・Editの前後等）になる。
# - 作業区間は、Writeツール・Editツールでタスク毎引継ぎ資料を保存した時にまとめて書き込む。
#   Bash等で書き換えた場合は、その時点では書き込まれず、次に保存した時に書き込まれる。
#   保存しないままセッションを終えた（/clear等）場合、残りの作業区間は書き込まれない。
# - 同じセッションで複数のタスクを扱った場合、あるタスクの引継ぎ資料を保存した後の作業区間は、
#   次に保存した引継ぎ資料へ書き込まれる。
#
# テスト用に、環境変数HOJOU_WORKLOG_NOW（yyyy-MM-ddTHH:mm:ss）で現在時刻を指定できる。

$ErrorActionPreference = "Stop"

$timeFormat = "yyyy-MM-ddTHH:mm:ss"
$logTimeFormat = "yyyy-MM-dd HH:mm"
$handoffPattern = '^引継ぎ資料[\\/]タスク毎[\\/][^\\/]+_引継書\.md$'
$logLinePattern = '^- 開始: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}) / 終了: (\d{4}-\d{2}-\d{2} \d{2}:\d{2})$'
$stateRetentionDays = 30
$utf8 = New-Object System.Text.UTF8Encoding($false)
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-Time([string]$text, [string]$format) {
    return [DateTime]::ParseExact($text, $format, $invariantCulture)
}

function Read-HookInput {
    $stdin = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($stdin, $utf8)
    $raw = $reader.ReadToEnd()
    return ($raw | ConvertFrom-Json)
}

function Get-StateDir {
    $tempRoot = [System.IO.Path]::GetTempPath()
    return (Join-Path $tempRoot "hojou-worklog")
}

function Read-State([string]$statePath) {
    $state = @{ open = $null; last = $null; segments = @() }
    if (-not (Test-Path -LiteralPath $statePath)) {
        return $state
    }
    $raw = [System.IO.File]::ReadAllText($statePath, $utf8)
    $saved = $raw | ConvertFrom-Json
    $state.open = $saved.open
    $state.last = $saved.last
    foreach ($segment in @($saved.segments)) {
        if ($null -ne $segment) {
            $state.segments += @{ start = $segment.start; end = $segment.end }
        }
    }
    return $state
}

function Write-State([string]$statePath, $state) {
    $stateDir = Split-Path -Parent $statePath
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    $json = ConvertTo-Json -InputObject $state -Depth 5 -Compress
    [System.IO.File]::WriteAllText($statePath, $json, $utf8)
}

function Remove-OldState([string]$stateDir) {
    $limit = (Get-Date).AddDays(-$stateRetentionDays)
    $oldFiles = Get-ChildItem -LiteralPath $stateDir -Filter "*.json" -File | Where-Object { $_.LastWriteTime -lt $limit }
    foreach ($oldFile in $oldFiles) {
        Remove-Item -LiteralPath $oldFile.FullName -Force
    }
}

# 開いている作業区間を終了し、記録済みの作業区間に加える
function Close-Segment($state, [string]$endText) {
    if ($null -eq $state.open) {
        return
    }
    if ([string]::CompareOrdinal($endText, $state.open) -lt 0) {
        $endText = $state.open
    }
    $state.segments += @{ start = $state.open; end = $endText }
    $state.open = $null
}

# 保存したファイルがタスク毎引継ぎ資料であれば、その絶対パスを返す
function Get-HandoffPath($hookInput) {
    $filePath = [string]$hookInput.tool_input.file_path
    if ([string]::IsNullOrEmpty($filePath)) {
        return $null
    }
    $projectDir = $env:CLAUDE_PROJECT_DIR
    if ([string]::IsNullOrEmpty($projectDir)) {
        $projectDir = [string]$hookInput.cwd
    }
    if ([string]::IsNullOrEmpty($projectDir)) {
        return $null
    }
    $fullPath = [System.IO.Path]::GetFullPath($filePath)
    $projectFullPath = [System.IO.Path]::GetFullPath($projectDir)
    $rootPath = $projectFullPath.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $null
    }
    $relativePath = $fullPath.Substring($rootPath.Length)
    if ($relativePath -notmatch $handoffPattern) {
        return $null
    }
    if (-not (Test-Path -LiteralPath $fullPath)) {
        return $null
    }
    return $fullPath
}

# 作業区間を分単位の行（開始は切り捨て・終了は切り上げ）にし、重なる・接する行をまとめる
function Merge-LogRows($rows, $segments) {
    foreach ($segment in $segments) {
        $startTime = ConvertTo-Time $segment.start $timeFormat
        $endTime = ConvertTo-Time $segment.end $timeFormat
        $rowStart = New-Object DateTime($startTime.Year, $startTime.Month, $startTime.Day, $startTime.Hour, $startTime.Minute, 0)
        $rowEnd = New-Object DateTime($endTime.Year, $endTime.Month, $endTime.Day, $endTime.Hour, $endTime.Minute, 0)
        if ($rowEnd -lt $endTime) {
            $rowEnd = $rowEnd.AddMinutes(1)
        }
        if ($rowEnd -le $rowStart) {
            $rowEnd = $rowStart.AddMinutes(1)
        }
        $lastIndex = $rows.Count - 1
        if ($lastIndex -ge 0 -and $rowStart -ge $rows[$lastIndex].start -and $rowStart -le $rows[$lastIndex].end) {
            if ($rowEnd -gt $rows[$lastIndex].end) {
                $rows[$lastIndex].end = $rowEnd
            }
        } else {
            $rows.Add(@{ start = $rowStart; end = $rowEnd })
        }
    }
}

function Write-WorkLog([string]$path, $segments) {
    $bytes = [System.IO.File]::ReadAllBytes($path)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    $offset = 0
    if ($hasBom) {
        $offset = 3
    }
    $text = $utf8.GetString($bytes, $offset, $bytes.Length - $offset)
    $newline = "`n"
    if ($text.Contains("`r`n")) {
        $newline = "`r`n"
    }
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.AddRange([string[]]($text -split "\r?\n"))
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq "") {
        $lines.RemoveAt($lines.Count - 1)
    }

    $headingIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^##\s*作業ログ\s*$') {
            $headingIndex = $i
            break
        }
    }
    $sectionEnd = $lines.Count
    if ($headingIndex -ge 0) {
        for ($i = $headingIndex + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^##\s' -or $lines[$i] -match '^---\s*$') {
                $sectionEnd = $i
                break
            }
        }
    }

    # 「## 作業ログ」の本文（テンプレートの記載例と前後の空行を除く）
    $body = New-Object System.Collections.Generic.List[string]
    if ($headingIndex -ge 0) {
        for ($i = $headingIndex + 1; $i -lt $sectionEnd; $i++) {
            if ($lines[$i] -notmatch '^\s*<.+>\s*$') {
                $body.Add($lines[$i])
            }
        }
    }
    while ($body.Count -gt 0 -and $body[0].Trim() -eq "") {
        $body.RemoveAt(0)
    }
    while ($body.Count -gt 0 -and $body[$body.Count - 1].Trim() -eq "") {
        $body.RemoveAt($body.Count - 1)
    }

    # 直前の作業ログの行を、まとめる対象に含める
    $rows = New-Object System.Collections.Generic.List[object]
    if ($body.Count -gt 0) {
        $lastLine = $body[$body.Count - 1].Trim()
        if ($lastLine -match $logLinePattern) {
            $lastStart = ConvertTo-Time $Matches[1] $logTimeFormat
            $lastEnd = ConvertTo-Time $Matches[2] $logTimeFormat
            if ($lastEnd -gt $lastStart) {
                $rows.Add(@{ start = $lastStart; end = $lastEnd })
                $body.RemoveAt($body.Count - 1)
            }
        }
    }
    Merge-LogRows $rows $segments
    foreach ($row in $rows) {
        $rowText = "- 開始: " + $row.start.ToString($logTimeFormat, $invariantCulture) + " / 終了: " + $row.end.ToString($logTimeFormat, $invariantCulture)
        $body.Add($rowText)
    }

    $result = New-Object System.Collections.Generic.List[string]
    if ($headingIndex -ge 0) {
        for ($i = 0; $i -le $headingIndex; $i++) {
            $result.Add($lines[$i])
        }
        $result.Add("")
        $result.AddRange($body)
        if ($sectionEnd -lt $lines.Count) {
            $result.Add("")
            for ($i = $sectionEnd; $i -lt $lines.Count; $i++) {
                $result.Add($lines[$i])
            }
        }
    } else {
        $result.AddRange($lines)
        $result.Add("")
        $result.Add("## 作業ログ")
        $result.Add("")
        $result.AddRange($body)
    }

    $newText = [string]::Join($newline, $result) + $newline
    $newBytes = $utf8.GetBytes($newText)
    if ($hasBom) {
        $bom = [byte[]](0xEF, 0xBB, 0xBF)
        $newBytes = $bom + $newBytes
    }
    [System.IO.File]::WriteAllBytes($path, [byte[]]$newBytes)
}

function Invoke-WorklogHook {
    $hookInput = Read-HookInput
    $sessionId = [string]$hookInput.session_id
    # セッションIDは一時ファイル名に使うため、英数字・ハイフン・アンダースコア以外を含む場合は何もしない
    if ($sessionId -notmatch '^[A-Za-z0-9_-]+$') {
        return
    }
    $stateDir = Get-StateDir
    $statePath = Join-Path $stateDir ($sessionId + ".json")
    $state = Read-State $statePath

    $now = Get-Date
    if (-not [string]::IsNullOrEmpty($env:HOJOU_WORKLOG_NOW)) {
        $now = ConvertTo-Time $env:HOJOU_WORKLOG_NOW $timeFormat
    }
    $nowText = $now.ToString($timeFormat, $invariantCulture)
    $eventName = [string]$hookInput.hook_event_name
    $toolName = [string]$hookInput.tool_name
    $handoffPath = $null

    switch ($eventName) {
        "UserPromptSubmit" {
            # 前の応答が中断されてStopが起きなかった場合は、最後にこのhookが動いた時刻で終了する
            if ($null -ne $state.open) {
                Close-Segment $state $state.last
            }
            $state.open = $nowText
        }
        "PreToolUse" {
            if ($toolName -eq "AskUserQuestion") {
                Close-Segment $state $nowText
            }
        }
        "PostToolUseFailure" {
            if ($toolName -eq "AskUserQuestion" -and $null -eq $state.open) {
                $state.open = $nowText
            }
        }
        "PostToolUse" {
            if ($toolName -eq "AskUserQuestion") {
                if ($null -eq $state.open) {
                    $state.open = $nowText
                }
            } elseif ($toolName -eq "Write" -or $toolName -eq "Edit") {
                $handoffPath = Get-HandoffPath $hookInput
                if ($null -ne $handoffPath) {
                    Close-Segment $state $nowText
                    $state.open = $nowText
                }
            }
        }
        "Stop" {
            Close-Segment $state $nowText
        }
    }
    $state.last = $nowText

    if ($null -ne $handoffPath -and $state.segments.Count -gt 0) {
        Write-WorkLog $handoffPath $state.segments
        $state.segments = @()
    }
    Write-State $statePath $state
    Remove-OldState $stateDir
}

try {
    Invoke-WorklogHook
    exit 0
} catch {
    [Console]::Error.WriteLine("worklog-hook.ps1: " + $_.Exception.Message)
    exit 1
}
