# タスク毎引継ぎ資料の「## 作業ログ」を自動で記録するClaude Codeのhook（worklog-hook.ps1）の
# 設定を、利用側プロジェクトの.claude/settings.jsonへマージする。
#
# 背景：
# - 引継書ルール「作業時間の計測」の作業ログは、AIが記載すると形式の誤りや記載漏れが起きる。
#   hookで記録することで、AIの記載に頼らずに作業ログを残す（任意設定）。
# - .claude/settings.jsonは利用側プロジェクト固有の他設定（permissions・他のhooks・env等）と
#   共存する必要があるため、既存設定は変更せず、未設定のhookのみを追記するマージ処理を行う。
#
# 実行タイミング：
# - 利用側プロジェクトで作業ログの自動記録を使い始める時（リポジトリを新規cloneした直後を含む）
#
# 使い方（利用側プロジェクトのルートで実行する）：
#   powershell -ExecutionPolicy Bypass -File hojou/scripts/setup-worklog-hooks.ps1
#
# 限界（必ず確認すること）：
# - hookはClaude Codeでのみ動作する。Codex等の他のAIエージェントでは、引継書ルールに従い
#   AIが作業ログを記載する。
# - 作業区間の記録方法と限界は、worklog-hook.ps1の冒頭を参照すること。
# - 実際に作業ログが書き込まれるかは、使用しているClaude Codeのバージョン、および
#   .claude/settings.local.json等の他の設定ファイルとの組み合わせに依存するため、
#   導入後にタスク毎引継ぎ資料を保存して、作業ログが書き込まれることを確認すること。

$ErrorActionPreference = "Stop"

# このスクリプトは <利用側プロジェクト>/hojou/scripts/ に配置される前提。
$submoduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $submoduleRoot
$submoduleName = Split-Path -Leaf $submoduleRoot

$hookScriptName = "worklog-hook.ps1"
$hookScriptPath = '${CLAUDE_PROJECT_DIR}/' + $submoduleName + "/scripts/" + $hookScriptName

# hookの種類ごとの対象ツール（matcher）。$nullはmatcherを指定しない（すべてが対象）
$requiredHooks = [ordered]@{
    "UserPromptSubmit"   = $null
    "PreToolUse"         = "AskUserQuestion"
    "PostToolUse"        = "AskUserQuestion|Write|Edit"
    "PostToolUseFailure" = "AskUserQuestion"
    "Stop"               = $null
}

function New-HookGroup($matcher) {
    $hook = [ordered]@{
        type    = "command"
        command = "powershell"
        args    = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $hookScriptPath)
        timeout = 30
    }
    $group = [ordered]@{}
    if ($null -ne $matcher) {
        $group.matcher = $matcher
    }
    $group.hooks = @($hook)
    return (New-Object PSObject -Property $group)
}

# 既存のhookの中に、worklog-hook.ps1を呼ぶものがあるか
function Test-WorklogHookExists($groups) {
    foreach ($group in @($groups)) {
        if ($null -eq $group) {
            continue
        }
        foreach ($hook in @($group.hooks)) {
            if ($null -eq $hook) {
                continue
            }
            $texts = @([string]$hook.command) + @($hook.args | ForEach-Object { [string]$_ })
            foreach ($text in $texts) {
                if ($text -like "*$hookScriptName*") {
                    return $true
                }
            }
        }
    }
    return $false
}

$settingsDir = Join-Path $repoRoot ".claude"
$settingsPath = Join-Path $settingsDir "settings.json"

if (-not (Test-Path $settingsDir)) {
    New-Item -ItemType Directory -Path $settingsDir -Force | Out-Null
}

if (Test-Path $settingsPath) {
    $raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        $settings = New-Object PSObject
    } else {
        $settings = $raw | ConvertFrom-Json
    }
} else {
    $settings = New-Object PSObject
}

if (-not (Get-Member -InputObject $settings -Name "hooks" -MemberType NoteProperty)) {
    $settings | Add-Member -MemberType NoteProperty -Name "hooks" -Value (New-Object PSObject)
}

$addedEvents = @()
foreach ($eventName in $requiredHooks.Keys) {
    if (-not (Get-Member -InputObject $settings.hooks -Name $eventName -MemberType NoteProperty)) {
        $settings.hooks | Add-Member -MemberType NoteProperty -Name $eventName -Value @()
    }
    $groups = @($settings.hooks.$eventName)
    if (-not (Test-WorklogHookExists $groups)) {
        $groups += New-HookGroup $requiredHooks[$eventName]
        $addedEvents += $eventName
    }
    $settings.hooks.$eventName = $groups
}

$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))

if ($addedEvents.Count -gt 0) {
    Write-Output "追加したhook（作業ログの自動記録）:"
    $addedEvents | ForEach-Object { Write-Output "  - $_" }
} else {
    Write-Output "追加すべきhookはありませんでした（既に設定済みです）。"
}
Write-Output "更新先: $settingsPath"
