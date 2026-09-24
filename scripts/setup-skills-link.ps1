# 本リポジトリ（hojou）側Skill（.agents/skills/）を、
# 利用側プロジェクトからAIエージェント（Claude Code・OpenAI Codex等）に認識させるための
# ディレクトリジャンクションを作成する。
#
# 背景：
# - 本リポジトリは利用側プロジェクトのルート直下にgit submoduleとして取り込まれる想定だが、
#   Claude Codeはプロジェクトルート直下の.claude/skills/を、OpenAI Codexはプロジェクト
#   ルート直下の.agents/skills/をそれぞれSkillとして自動認識する
#   （submodule配下の.agents/skills/はどちらのツールからも自動認識されない）。
# - Skill本体は.agents/skills/（Codex等が標準で認識するパス。参照：
#   https://learn.chatgpt.com/docs/build-skills ）に一本化して置き、
#   利用側プロジェクトの.claude/skills・.agents/skillsの両方から、
#   この実体を指すジャンクションで参照する。
# - 本来はシンボリックリンクで実体を見せたいが、Windows標準環境でのシンボリックリンク
#   作成には管理者権限または開発者モードが必要。
# - ディレクトリジャンクション（mklink /J相当）は権限不要で作成できるため、
#   代替手段として使用する。
#
# 実行タイミング：
# - 利用側プロジェクトでリポジトリを新規clone・pullした直後
# - 本リポジトリ側にSkillを新規追加した直後
# - 本リポジトリ側でSkill本体の配置（.agents/skills/）を変更した直後
#
# 使い方（利用側プロジェクトのルートで実行する）：
#   powershell -ExecutionPolicy Bypass -File hojou/scripts/setup-skills-link.ps1

$ErrorActionPreference = "Stop"

# このスクリプトは <利用側プロジェクト>/hojou/scripts/ に配置される前提。
$submoduleRoot = Split-Path -Parent $PSScriptRoot
$repoRoot = Split-Path -Parent $submoduleRoot
$target = Join-Path $submoduleRoot ".agents\skills"

if (-not (Test-Path $target)) {
    Write-Error "リンク先が見つからない: $target `n（hojouのsubmoduleが初期化されているか確認すること：git submodule update --init）"
    exit 1
}

function Set-SkillsJunction {
    param(
        [string]$LinkParent,
        [string]$Target
    )

    $link = Join-Path $LinkParent "skills"
    New-Item -ItemType Directory -Force -Path $LinkParent | Out-Null

    if (Test-Path $link) {
        $item = Get-Item $link -Force
        if ($item.LinkType -eq "Junction") {
            $currentTarget = ($item.Target | Select-Object -First 1).TrimEnd('\')
            $expectedTarget = $Target.TrimEnd('\')
            if ($currentTarget -eq $expectedTarget) {
                Write-Output "既にジャンクション作成済み: $link -> $currentTarget"
                return
            }
            Write-Output "参照先が古いため張り直す: $link （$currentTarget -> $expectedTarget）"
            $item.Delete()
        } else {
            Write-Error "$link は既存の非ジャンクション（通常のディレクトリ/ファイル）のため、上書きしない。手動確認すること。"
            exit 1
        }
    }

    New-Item -ItemType Junction -Path $link -Target $Target | Out-Null
    Write-Output "ジャンクション作成完了: $link -> $Target"
}

Set-SkillsJunction -LinkParent (Join-Path $repoRoot ".claude") -Target $target
Set-SkillsJunction -LinkParent (Join-Path $repoRoot ".agents") -Target $target
