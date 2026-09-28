# Claude Codeのhookとして、AIの作業区間（ユーザーの返事待ちを除く）を秒単位で記録する。
# 記録した作業区間は、AIがコミットの直前にworklog-record.ps1を実行した時に、
# 指定したタスク毎引継ぎ資料の「## 作業ログ」へ書き込まれる。
#
# 背景：
# - 引継書ルール「作業時間の計測」では、作業ログの開始・終了時刻をAIが記載するが、
#   AIの記載では、形式の誤り（日付のみ・「頃」等）や開始時刻の抜けが起きる。
#   hookで記録することで、AIの記載に頼らずに作業ログを残す。
# - 書き込み先のタスク毎引継ぎ資料はhookでは決められないため、書き込みはworklog-record.ps1で行う。
#
# 動作（hookの種類ごと。hookの登録はsetup-worklog-hooks.ps1で行う）：
# - SessionStart（セッションの開始・再開・/clear・要約の後）：セッションIDと、
#   worklog-record.ps1の実行方法を会話へ出力する。作業区間は変更しない。
# - UserPromptSubmit（ユーザーの発言時）：作業区間を開始する。
# - PreToolUse（AskUserQuestionの直前）：作業区間を終了する（回答待ちを除くため）。
# - PostToolUse・PostToolUseFailure（AskUserQuestionの後）：作業区間を開始する。
# - Stop（AIの応答の終了時）：作業区間を終了する。
# - PostToolUse（Write・Editの後）：最後にこのhookが動いた時刻のみを更新する
#   （応答が中断された場合の、作業区間の終了時刻に使う）。
# - 記録途中の作業区間は、セッションごとに一時フォルダ（%TEMP%\hojou-worklog\）へ保存する
#   （形式はworklog-common.ps1参照）。30日以上更新のないものは削除する。
#
# 限界（必ず確認すること）：
# - 権限確認（ツール実行の許可）の待ち時間は、作業区間から除けない。
# - ユーザーが応答を中断した場合（Stopが起きない）、その作業区間の終了は、最後にこのhookが
#   動いた時刻（AskUserQuestion・Write・Editの前後、worklog-record.ps1の実行時等）になる。
# - worklog-record.ps1を実行した後の作業区間（コミット・最後の返答等）は、同じセッションで
#   次にworklog-record.ps1を実行した時に書き込まれる。実行しないままセッションを終えた
#   （/clear等）場合、残りの作業区間は書き込まれない。
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

function Invoke-WorklogHook {
    $hookInput = Read-HookInput
    $sessionId = [string]$hookInput.session_id
    $statePath = Get-StatePath $sessionId
    if ($null -eq $statePath) {
        return
    }
    $eventName = [string]$hookInput.hook_event_name
    if ($eventName -eq "SessionStart") {
        # 再開時等に「最後にこのhookが動いた時刻」を更新すると、中断された作業区間の終了が再開時刻になるため、
        # 作業区間の記録は変更しない
        Write-SessionContext $sessionId
        return
    }

    $state = Read-State $statePath
    $nowText = Get-NowText
    $toolName = [string]$hookInput.tool_name

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
            if ($toolName -eq "AskUserQuestion" -and $null -eq $state.open) {
                $state.open = $nowText
            }
        }
        "Stop" {
            Close-Segment $state $nowText
        }
    }
    $state.last = $nowText

    Write-State $statePath $state
    Remove-OldState (Get-StateDir)
}

try {
    Invoke-WorklogHook
    exit 0
} catch {
    Write-Utf8Error ("worklog-hook.ps1: " + $_.Exception.Message)
    exit 1
}
