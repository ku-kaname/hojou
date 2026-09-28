# Claude Codeの会話記録（transcript）から作業区間を求め、タスク毎引継ぎ資料
# （引継ぎ資料/タスク毎/<バックログ名称>_<タスク名>_引継書.md）の「## 作業ログ」へ書き込む。
# AIが、タスク毎引継ぎ資料をコミットする直前に実行する。
#
# 背景：
# - 作業区間をどのタスクの作業ログへ書き込むかは、会話記録からは分からない。タスク毎引継ぎ資料の
#   保存時に書き込むと、保存からコミットまでの作業区間が、次に保存した（別のタスクの）引継ぎ資料へ
#   書き込まれる。そのため、書き込み先と書き込むタイミングを、AIがこのスクリプトの実行で指定する。
# - 時刻を分単位に丸めると、タスクを切り替えた時に前後のタスクの作業ログの行が重なり、
#   作業コスト計測ツールで二重に計上されるため、秒単位で書き込む。
#
# 使い方（利用側プロジェクトのルートで実行する。セッションIDは、セッションの開始時・要約の後等に
# worklog-hook.ps1が会話へ出力する）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File hojou/scripts/worklog-record.ps1 -SessionId <セッションID> -Path "<タスク毎引継ぎ資料のパス>"
#
# 動作：
# - 会話記録（パスはworklog-hook.ps1がセッションの開始時に保存する。保存したパスになければ、
#   Claude Codeの設定フォルダ（環境変数CLAUDE_CONFIG_DIR、なければ~/.claude）のprojects/から探す）の、
#   前回の書き込み以降の部分から、次のように作業区間を求める。
#   - ユーザーの発言（ツールの実行結果・要約・中断の記録等を除く）から、AIの応答・ツールの実行結果の
#     うち次の発言より前の最後のものまでを、1つの作業区間とする（発言の間の返事待ちを除くため）。
#   - AskUserQuestion（選択式の質問）を呼んでから回答されるまでは、作業区間から除く。
#   - 実行した時点の作業区間は、実行した時刻で終了する（実行はAIの応答中に行うため）。
#     それ以降の作業区間は、次の実行時に、実行した時刻から続けて求める。
#   - 時刻はローカル時刻に直し、秒未満を切り捨てる。
# - 求めた作業区間を、「## 作業ログ」の末尾へ
#   「- 開始: yyyy-mm-dd hh:mm:ss / 終了: yyyy-mm-dd hh:mm:ss」の形式で書き込み、書き込んだ行を表示する。
# - 長さ0の作業区間は書き込まない。重なる・接する（終了と次の開始が同じ時刻の）作業区間は1行にまとめる。
#   直前の作業ログの行が同じ形式であれば、その行もまとめる対象に含める（分単位の行等は変更しない）。
# - 「## 作業ログ」の中のテンプレートの記載例（<...>の行）は、書き込み時に削除する。
#   「## 作業ログ」がなければ、ファイルの末尾に追加する。
# - 書き込む作業区間がなければ、タスク毎引継ぎ資料は変更しない。
#
# 限界（必ず確認すること）：
# - 権限確認（ツール実行の許可）の待ち時間は、作業区間から除けない。
# - 実行した後の作業区間（コミット・最後の返答等）は、同じセッションで次に実行した時に書き込まれる。
#   実行しないままセッションを終えた（/clear等）場合、残りの作業区間は書き込まれない。
# - 会話記録の形式はClaude Codeの内部の形式であり、公開された仕様ではない。Claude Codeの更新で
#   形式が変わると、作業区間を正しく求められなくなる可能性がある。会話記録が見つからない場合は、
#   エラーで終了する。
# - 指定したセッションの保存内容がない場合（hookが未導入・セッションIDの誤り等）は、エラーで終了する。
# - 1回の実行で、前回の書き込み以降のすべての作業区間を書き込む。前回の書き込み以降に
#   複数のタスクの作業をした場合も、指定したタスク毎引継ぎ資料へまとめて書き込む。
#
# テスト用に、環境変数HOJOU_WORKLOG_NOW（yyyy-MM-ddTHH:mm:ss）で現在時刻を指定できる。

param(
    [string]$SessionId,
    [string]$Path
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "worklog-common.ps1")

$logTimeFormat = "yyyy-MM-dd HH:mm:ss"
$handoffPattern = '^引継ぎ資料[\\/]タスク毎[\\/][^\\/]+_引継書\.md$'
$logLinePattern = '^- 開始: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) / 終了: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})$'

# このスクリプトは <利用側プロジェクト>/hojou/scripts/ に配置される前提。
$submoduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $submoduleRoot

# 指定したパスが利用側プロジェクトのタスク毎引継ぎ資料であれば、その絶対パスを返す
function Resolve-HandoffPath([string]$filePath) {
    if (-not [System.IO.Path]::IsPathRooted($filePath)) {
        $filePath = Join-Path (Get-Location).Path $filePath
    }
    $fullPath = [System.IO.Path]::GetFullPath($filePath)
    $rootPath = [System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
    if (-not $fullPath.StartsWith($rootPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw ("利用側プロジェクト（" + $repoRoot + "）の外のファイルは指定できません: " + $fullPath)
    }
    $relativePath = $fullPath.Substring($rootPath.Length)
    if ($relativePath -notmatch $handoffPattern) {
        throw ("タスク毎引継ぎ資料（引継ぎ資料/タスク毎/<バックログ名称>_<タスク名>_引継書.md）ではありません: " + $relativePath)
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw ("ファイルがありません: " + $relativePath)
    }
    return $fullPath
}

# 会話記録のパス。保存したパスになければ、Claude Codeの設定フォルダのprojects/から探す
function Resolve-TranscriptPath([string]$savedPath) {
    if (-not [string]::IsNullOrEmpty($savedPath) -and (Test-Path -LiteralPath $savedPath -PathType Leaf)) {
        return $savedPath
    }
    $configDir = $env:CLAUDE_CONFIG_DIR
    if ([string]::IsNullOrEmpty($configDir)) {
        $configDir = Join-Path ([Environment]::GetFolderPath("UserProfile")) ".claude"
    }
    $projectsDir = Join-Path $configDir "projects"
    if (Test-Path -LiteralPath $projectsDir -PathType Container) {
        foreach ($projectDir in (Get-ChildItem -LiteralPath $projectsDir -Directory)) {
            $candidate = Join-Path $projectDir.FullName ($SessionId + ".jsonl")
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }
    throw ("このセッションの会話記録が見つかりません: " + $SessionId)
}

# 会話記録の時刻（UTC等）をローカル時刻に直し、秒未満を切り捨てる
function ConvertFrom-TranscriptTime([string]$text) {
    $time = [DateTimeOffset]::Parse($text, $invariantCulture).LocalDateTime
    return $time.AddTicks(-($time.Ticks % [TimeSpan]::TicksPerSecond))
}

function Open-Segment($track, [DateTime]$time) {
    if ($time -lt $track.last) {
        $time = $track.last
    }
    $track.open = $time
    $track.last = $time
}

function Add-Activity($track, [DateTime]$time) {
    if ($time -gt $track.last) {
        $track.last = $time
    }
}

# 開いている作業区間を、最後の応答・ツールの実行結果の時刻で終了する
function Close-Segment($track) {
    if ($null -ne $track.open) {
        $track.segments.Add(@{ start = $track.open; end = $track.last })
        $track.open = $null
    }
}

function Get-ContentBlocks($message) {
    if ($null -eq $message) {
        return @()
    }
    $content = $message["content"]
    if ($content -is [System.Array]) {
        return $content
    }
    return @()
}

# ユーザーの発言か（ツールの実行結果・要約・スキル等の自動の追加・中断の記録を除く）
function Test-UserPrompt($entry, $message, $blocks) {
    if ($entry["isMeta"] -eq $true -or $entry["isCompactSummary"] -eq $true -or $null -eq $message) {
        return $false
    }
    $content = $message["content"]
    if ($content -is [string]) {
        return (-not $content.StartsWith("[Request interrupted"))
    }
    foreach ($block in $blocks) {
        if ($block["type"] -eq "text" -and ([string]$block["text"]).StartsWith("[Request interrupted")) {
            return $false
        }
    }
    return $true
}

# 会話記録の1件を、作業区間に反映する
function Add-TranscriptEntry($track, $entry) {
    $type = $entry["type"]
    if (($type -ne "user" -and $type -ne "assistant") -or $null -eq $entry["timestamp"]) {
        return
    }
    $time = ConvertFrom-TranscriptTime ([string]$entry["timestamp"])
    if ($time -lt $track.recorded) {
        return
    }
    if ($time -gt $track.now) {
        $time = $track.now
    }
    $message = $entry["message"]
    $blocks = @(Get-ContentBlocks $message)

    if ($type -eq "assistant") {
        # APIエラー等でClaude Code自身が作る応答は、AIの作業ではないため除く。
        # 選択式の質問の回答待ちの間の応答（同じ応答の後続部分等）も、作業区間を開かない
        if (($null -ne $message -and $message["model"] -eq "<synthetic>") -or $track.asks.Count -gt 0) {
            return
        }
        if ($null -eq $track.open) {
            Open-Segment $track $time
        } else {
            Add-Activity $track $time
        }
        foreach ($block in $blocks) {
            if ($block["type"] -eq "tool_use" -and $block["name"] -eq "AskUserQuestion") {
                $track.asks[[string]$block["id"]] = $true
            }
        }
        if ($track.asks.Count -gt 0) {
            Close-Segment $track
        }
        return
    }

    $results = @($blocks | Where-Object { $_["type"] -eq "tool_result" })
    if ($results.Count -gt 0) {
        $answered = $false
        foreach ($result in $results) {
            $toolUseId = [string]$result["tool_use_id"]
            if ($track.asks.ContainsKey($toolUseId)) {
                $track.asks.Remove($toolUseId)
                $answered = $true
            }
        }
        if ($track.asks.Count -gt 0) {
            return
        }
        if ($null -ne $track.open) {
            Add-Activity $track $time
        } elseif ($answered) {
            Open-Segment $track $time
        }
        return
    }
    if (Test-UserPrompt $entry $message $blocks) {
        $track.asks.Clear()
        Close-Segment $track
        Open-Segment $track $time
    }
}

# 会話記録のoffset（バイト）以降の完全な行を読んで作業区間を求め、読み終えた位置を返す
function Read-Transcript($track, [string]$transcriptPath, [long]$offset) {
    Add-Type -AssemblyName System.Web.Extensions
    $serializer = New-Object System.Web.Script.Serialization.JavaScriptSerializer
    $serializer.MaxJsonLength = [int]::MaxValue
    $serializer.RecursionLimit = 1000

    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $stream = New-Object System.IO.FileStream($transcriptPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, $share)
    try {
        # 読み終えた位置が行の区切りでなければ（会話記録が書き直された等）、先頭から読む
        if ($offset -gt $stream.Length) {
            $offset = 0
        }
        if ($offset -gt 0) {
            [void]$stream.Seek($offset - 1, [System.IO.SeekOrigin]::Begin)
            if ($stream.ReadByte() -ne 10) {
                $offset = 0
            }
        }
        [void]$stream.Seek($offset, [System.IO.SeekOrigin]::Begin)
        $position = $offset
        $buffer = New-Object byte[] 1048576
        $pending = New-Object System.IO.MemoryStream
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $start = 0
            while ($start -lt $read) {
                $index = [Array]::IndexOf($buffer, [byte]10, $start, $read - $start)
                if ($index -lt 0) {
                    $pending.Write($buffer, $start, $read - $start)
                    break
                }
                $pending.Write($buffer, $start, $index - $start)
                $line = $utf8.GetString($pending.GetBuffer(), 0, [int]$pending.Length)
                $position += $pending.Length + 1
                $pending.SetLength(0)
                $start = $index + 1
                if (-not ($line.Contains('"type":"user"') -or $line.Contains('"type":"assistant"'))) {
                    continue
                }
                try {
                    $entry = $serializer.DeserializeObject($line)
                } catch {
                    continue
                }
                if ($entry -is [System.Collections.Generic.Dictionary[string, object]]) {
                    Add-TranscriptEntry $track $entry
                }
            }
        }
    } finally {
        $stream.Dispose()
    }
    return $position
}

# 作業区間を行にし、重なる・接する行をまとめる（長さ0の作業区間は除く）
function Merge-LogRows($rows, $segments) {
    foreach ($segment in $segments) {
        $rowStart = $segment.start
        $rowEnd = $segment.end
        if ($rowEnd -le $rowStart) {
            continue
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

function Format-LogRow($row) {
    return ("- 開始: " + $row.start.ToString($logTimeFormat, $invariantCulture) + " / 終了: " + $row.end.ToString($logTimeFormat, $invariantCulture))
}

# 「## 作業ログ」へ作業区間を書き込み、書き込んだ行（まとめた直前の行を含む）を返す
function Write-WorkLog([string]$path, $segments) {
    $newRows = New-Object System.Collections.Generic.List[object]
    Merge-LogRows $newRows $segments
    if ($newRows.Count -eq 0) {
        return @()
    }

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

    # 直前の作業ログの行が秒単位の形式であれば、まとめる対象に含める
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
    $rowTexts = @()
    foreach ($row in $rows) {
        $rowText = Format-LogRow $row
        $body.Add($rowText)
        $rowTexts += $rowText
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
    return $rowTexts
}

function Invoke-WorklogRecord {
    if ([string]::IsNullOrEmpty($SessionId) -or [string]::IsNullOrEmpty($Path)) {
        throw '使い方: powershell -NoProfile -ExecutionPolicy Bypass -File hojou/scripts/worklog-record.ps1 -SessionId <セッションID> -Path "<タスク毎引継ぎ資料のパス>"'
    }
    $statePath = Get-StatePath $SessionId
    if ($null -eq $statePath) {
        throw ("セッションIDが不正です: " + $SessionId)
    }
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw ("このセッションの記録がありません（SessionStartのhookが導入されていないか、セッションIDが誤っています）: " + $SessionId)
    }
    $handoffPath = Resolve-HandoffPath $Path

    $state = Read-State $statePath
    if ([string]::IsNullOrEmpty($state.recorded)) {
        throw ("このセッションの記録に前回書き込んだ時刻がありません: " + $statePath)
    }
    $transcriptPath = Resolve-TranscriptPath $state.transcript
    $nowText = Get-NowText
    $now = ConvertTo-Time $nowText $timeFormat
    $recorded = ConvertTo-Time $state.recorded $timeFormat

    # 前回の書き込みはAIの応答中に行うため、作業区間が開いた状態から求め始める
    $track = @{
        recorded = $recorded
        now      = $now
        open     = $recorded
        last     = $recorded
        asks     = @{}
        segments = New-Object System.Collections.Generic.List[object]
    }
    $offset = Read-Transcript $track $transcriptPath $state.offset
    if ($null -ne $track.open) {
        Add-Activity $track $now
        Close-Segment $track
    }

    $rowTexts = @(Write-WorkLog $handoffPath $track.segments)
    Write-State $statePath @{ transcript = $transcriptPath; recorded = $nowText; offset = $offset }

    $relativePath = $handoffPath.Substring(([System.IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')).Length + 1)
    if ($rowTexts.Count -eq 0) {
        Write-Utf8Output ("書き込む作業区間はありません（" + $relativePath + "は変更していません）。")
    } else {
        Write-Utf8Output ("作業ログへ書き込みました: " + $relativePath)
        foreach ($rowText in $rowTexts) {
            Write-Utf8Output $rowText
        }
    }
}

try {
    Invoke-WorklogRecord
    exit 0
} catch {
    Write-Utf8Error ("worklog-record.ps1: " + $_.Exception.Message)
    exit 1
}
