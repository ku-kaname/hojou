# Claude CodeのSessionStartのhookとして、セッションIDと会話記録（transcript）のパスを保存し、
# セッションIDとworklog-record.ps1の実行方法を会話へ出力する。
# 作業区間は、AIがコミットの直前にworklog-record.ps1を実行した時に会話記録から求め、
# 指定したタスク毎引継ぎ資料の「## 作業ログ」へ書き込む。
#
# 背景：
# - 引継書ルール「作業時間の計測」では、作業ログの開始・終了時刻をAIが記載するが、
#   AIの記載では、形式の誤り（日付のみ・「頃」等）や開始時刻の抜けが起きる。
#   会話記録の時刻から求めることで、AIの記載に頼らずに作業ログを残す。
# - 会話記録には、ユーザーの発言・AIの応答・ツールの実行結果が時刻とともに残るため、
#   発言ごと・ツールの実行ごとのhookで時刻を記録する必要はない。hookは、worklog-record.ps1が
#   会話記録を探すためのパスの保存と、AIへのセッションIDの伝達のみを行う。
#
# 動作（hookの登録はsetup-worklog-hooks.ps1で行う）：
# - SessionStart（セッションの開始・再開・/clear・要約の後）：
#   - このセッションの保存内容がなければ作成する（前回書き込んだ時刻は現在時刻、会話記録の読み終えた
#     位置は現在の会話記録の末尾）。あれば、会話記録のパスのみを更新する（パスが変わった場合は、
#     読み終えた位置を先頭に戻す）。
#   - セッションIDと、worklog-record.ps1の実行方法を会話へ出力する。
#   - 保存内容は一時フォルダ（%TEMP%\hojou-worklog\）に置き（形式はworklog-common.ps1参照）、
#     30日以上更新のないものは削除する。
# - SessionStart以外（以前の版で登録したhook）：何もしない。
#
# テスト用に、環境変数HOJOU_WORKLOG_NOW（yyyy-MM-ddTHH:mm:ss）で現在時刻を指定できる。

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "worklog-common.ps1")

function Read-HookInput {
    $stdin = [Console]::OpenStandardInput()
    $reader = New-Object System.IO.StreamReader($stdin, $utf8)
    $raw = $reader.ReadToEnd()
    return ($raw | ConvertFrom-Json)
}

# 文字コードの設定に左右されないよう、ASCII以外の文字を\uXXXXで表したJSONの文字列にする
function ConvertTo-JsonString([string]$text) {
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($ch in $text.ToCharArray()) {
        $code = [int]$ch
        if ($ch -eq '"' -or $ch -eq '\') {
            [void]$builder.Append('\').Append($ch)
        } elseif ($code -lt 0x20 -or $code -gt 0x7E) {
            [void]$builder.Append('\u').Append($code.ToString("x4"))
        } else {
            [void]$builder.Append($ch)
        }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

# セッションIDと、worklog-record.ps1の実行方法を会話へ出力する
function Write-SessionContext([string]$sessionId) {
    $submoduleName = Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)
    $recordCommand = "powershell -NoProfile -ExecutionPolicy Bypass -File " + $submoduleName + "/scripts/worklog-record.ps1 -SessionId " + $sessionId + ' -Path "<タスク毎引継ぎ資料のパス>"'
    $context = "作業ログの自動記録（" + $submoduleName + "/scripts/worklog-hook.ps1）が有効です。このセッションのセッションID: " + $sessionId + "`n" +
        "タスク毎引継ぎ資料をコミットする直前に、次のコマンドでそのタスク毎引継ぎ資料の「## 作業ログ」へ作業区間を書き込み、書き込まれたタスク毎引継ぎ資料も含めてコミットすること（引継書ルール「作業時間の計測」参照）。`n" +
        $recordCommand
    $json = '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":' + (ConvertTo-JsonString $context) + '}}'
    Write-Utf8Output $json
}

# 会話記録の現在の長さ（バイト）。まだなければ0
function Get-TranscriptLength([string]$transcriptPath) {
    if ([string]::IsNullOrEmpty($transcriptPath) -or -not (Test-Path -LiteralPath $transcriptPath -PathType Leaf)) {
        return [long]0
    }
    return (Get-Item -LiteralPath $transcriptPath).Length
}

function Invoke-WorklogHook {
    $hookInput = Read-HookInput
    if ([string]$hookInput.hook_event_name -ne "SessionStart") {
        return
    }
    $sessionId = [string]$hookInput.session_id
    $statePath = Get-StatePath $sessionId
    if ($null -eq $statePath) {
        return
    }
    $transcriptPath = [string]$hookInput.transcript_path

    if (Test-Path -LiteralPath $statePath) {
        $state = Read-State $statePath
        if (-not [string]::IsNullOrEmpty($transcriptPath) -and $transcriptPath -ne $state.transcript) {
            $state.transcript = $transcriptPath
            $state.offset = [long]0
        }
    } else {
        $state = @{ transcript = $transcriptPath; recorded = (Get-NowText); offset = (Get-TranscriptLength $transcriptPath) }
    }
    Write-State $statePath $state
    Remove-OldState (Get-StateDir)
    Write-SessionContext $sessionId
}

try {
    Invoke-WorklogHook
    exit 0
} catch {
    Write-Utf8Error ("worklog-hook.ps1: " + $_.Exception.Message)
    exit 1
}
