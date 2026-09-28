# worklog-hook.ps1が記録した作業区間を、タスク毎引継ぎ資料
# （引継ぎ資料/タスク毎/<バックログ名称>_<タスク名>_引継書.md）の「## 作業ログ」へ書き込む。
# AIが、タスク毎引継ぎ資料をコミットする直前に実行する。
#
# 背景：
# - hookでは、作業区間をどのタスクの作業ログへ書き込むかが分からない。タスク毎引継ぎ資料の保存時に
#   書き込むと、保存からコミットまでの作業区間が、次に保存した（別のタスクの）引継ぎ資料へ書き込まれる。
#   そのため、書き込み先と書き込むタイミングを、AIがこのスクリプトの実行で指定する。
# - 時刻を分単位に丸めると、タスクを切り替えた時に前後のタスクの作業ログの行が重なり、
#   作業コスト計測ツールで二重に計上されるため、秒単位で書き込む。
#
# 使い方（利用側プロジェクトのルートで実行する。セッションIDは、セッションの開始時・要約の後等に
# worklog-hook.ps1が会話へ出力する）：
#   powershell -NoProfile -ExecutionPolicy Bypass -File hojou/scripts/worklog-record.ps1 -SessionId <セッションID> -Path "<タスク毎引継ぎ資料のパス>"
#
# 動作：
# - 実行した時点で開いている作業区間は、その時刻で終了し、同じ時刻から次の作業区間を開始する。
# - そのセッションで前回の書き込み以降に記録した作業区間を、「## 作業ログ」の末尾へ
#   「- 開始: yyyy-mm-dd hh:mm:ss / 終了: yyyy-mm-dd hh:mm:ss」の形式で書き込み、書き込んだ行を表示する。
# - 長さ0の作業区間は書き込まない。重なる・接する（終了と次の開始が同じ時刻の）作業区間は1行にまとめる。
#   直前の作業ログの行が同じ形式であれば、その行もまとめる対象に含める（分単位の行等は変更しない）。
# - 「## 作業ログ」の中のテンプレートの記載例（<...>の行）は、書き込み時に削除する。
#   「## 作業ログ」がなければ、ファイルの末尾に追加する。
# - 書き込む作業区間がなければ、タスク毎引継ぎ資料は変更しない。
#
# 限界（必ず確認すること）：
# - 指定したセッションの記録がない場合（hookが未導入・セッションIDの誤り等）は、エラーで終了する。
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

# 作業区間を行にし、重なる・接する行をまとめる（長さ0の作業区間は除く）
function Merge-LogRows($rows, $segments) {
    foreach ($segment in $segments) {
        $rowStart = ConvertTo-Time $segment.start $timeFormat
        $rowEnd = ConvertTo-Time $segment.end $timeFormat
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
        throw ("このセッションの作業区間の記録がありません（hookが導入されていないか、セッションIDが誤っています）: " + $SessionId)
    }
    $handoffPath = Resolve-HandoffPath $Path

    $state = Read-State $statePath
    $nowText = Get-NowText
    if ($null -ne $state.open) {
        Close-Segment $state $nowText
        $state.open = $nowText
    }
    $state.last = $nowText

    $rowTexts = @(Write-WorkLog $handoffPath $state.segments)
    $state.segments = @()
    Write-State $statePath $state

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
