# AIエージェント（Claude Code）のgit/gh操作（Bash・PowerShellツール経由のコマンド実行）について、
# 自動承認モード（bypassPermissions等）が有効でも必ずユーザー確認を挟むようにする
# permissions.ask設定を、利用側プロジェクトの.claude/settings.jsonへマージする。
#
# 背景：
# - .agents/skills/はディレクトリジャンクションで利用側プロジェクトから参照させる運用ができるが
#   （setup-skills-link.ps1参照）、.claude/settings.jsonは利用側プロジェクト固有の他設定
#   （他のpermissionsルール・hooks・env等）と共存する必要があるため、ジャンクションや単純
#   コピーでは配布できない。既存設定は変更せず、未設定のルールのみを追記するマージ処理を行う。
#
# 実行タイミング：
# - 利用側プロジェクトでリポジトリを新規clone・pullした直後
#
# 使い方（利用側プロジェクトのルートで実行する）：
#   powershell -ExecutionPolicy Bypass -File hojou/scripts/setup-git-safety-settings.ps1
#
# 限界（必ず確認すること）：
# - permissions.askは複合コマンド文字列全体に対する判定であり、個々のサブコマンド単位では
#   検証しない（例：`git ... && rm -rf ...`のような複合コマンドは全体が対象になる）。
# - 実際に確認プロンプトが機能するかは、使用しているClaude Codeのバージョン・実行モード、
#   および.claude/settings.local.json等より優先度の高い設定ファイルとの競合に依存するため、
#   導入後に実際のgit/gh操作で確認が挟まることを確認すること。

$ErrorActionPreference = "Stop"

# このスクリプトは <利用側プロジェクト>/hojou/scripts/ に配置される前提。
$submoduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $submoduleRoot

$requiredAskRules = @(
    "Bash(git *)",
    "Bash(gh *)",
    "PowerShell(git *)",
    "PowerShell(gh *)"
)

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

if (-not (Get-Member -InputObject $settings -Name "permissions" -MemberType NoteProperty)) {
    $settings | Add-Member -MemberType NoteProperty -Name "permissions" -Value (New-Object PSObject)
}

if (-not (Get-Member -InputObject $settings.permissions -Name "ask" -MemberType NoteProperty)) {
    $settings.permissions | Add-Member -MemberType NoteProperty -Name "ask" -Value @()
}

$existingRules = @($settings.permissions.ask)
$addedRules = @()
foreach ($rule in $requiredAskRules) {
    if ($existingRules -notcontains $rule) {
        $existingRules += $rule
        $addedRules += $rule
    }
}
$settings.permissions.ask = $existingRules

$json = $settings | ConvertTo-Json -Depth 20
[System.IO.File]::WriteAllText($settingsPath, $json, (New-Object System.Text.UTF8Encoding($false)))

if ($addedRules.Count -gt 0) {
    Write-Output "追加した確認ルール:"
    $addedRules | ForEach-Object { Write-Output "  - $_" }
} else {
    Write-Output "追加すべきルールはありませんでした（既に設定済みです）。"
}
Write-Output "更新先: $settingsPath"
