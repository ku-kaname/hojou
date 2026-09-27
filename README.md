# hojou

AIエージェントと進めるシステム開発のための、工程ルール・テンプレート・Skills集です。
要件定義から設計、実装、単体テスト・結合テスト、プロジェクト完了、完了後の改修まで、作業の進め方と成果物の記録方法を揃えます。

開発プロジェクトにGitサブモジュールとして取り込み、AIエージェントから参照して使います。
工程ごとの成果物を残し、レビュー指摘や判断の経緯を次の作業へ引き継ぎたいプロジェクトを想定しています。

## できること

| 提供物 | 用途 |
|---|---|
| 工程ルール・チェックリスト | 各工程の作業手順やレビュー観点を揃える |
| 成果物テンプレート | 要件定義書・設計書・テスト仕様書・レビュー指摘表などの記載形式を揃える |
| AIエージェント用Skills | 工程の開始時に、必要な方針や手順を参照する |

## 対応範囲と前提条件

| 項目 | 対応範囲 |
|---|---|
| AIエージェント | Claude Codeを正式サポート |
| 技術スタック | FastAPIを正式サポート |
| その他 | OpenAI Codex向けのチェックリスト等は実験的提供、React等のチェックリストは参考情報。いずれも動作未検証・正式サポート対象外 |
| テスト工程 | 総合テスト・受入テストは範囲外です。要件に照らした確認と受け入れの判断は、利用者が行ってください |
| 動作確認環境 | Windows・PowerShell環境でのみ動作確認済み（Linux/macOSでの動作は未検証のため、本READMEでは案内していません） |
| リポジトリの取得・更新 | Gitが必要 |

GitHubのIssueやPRをCLIで操作する運用では、GitHub CLI（`gh`）と認証設定も必要です。

## 導入手順（Windows）

以下は、Git管理している利用側プロジェクトのルートで実行します。

### 1. サブモジュールを追加する

```powershell
git submodule add https://github.com/ku-kaname/hojou.git hojou
```

既にこのサブモジュールを含むプロジェクトを取得した場合は、追加の代わりに初期化します。

```powershell
git submodule update --init --recursive
```

### 2. AIエージェントの参照先を設定する

利用側プロジェクトのルートに`AGENTS.md`を作成し、次の行を記載します。
既存の`AGENTS.md`がある場合は、この行を追記してください。
プロジェクト固有のルールも同じファイルに記載できます。

```text
@hojou/AIエージェント指示書.md
```

Claude Codeから参照するため、同じ場所の`CLAUDE.md`に次の行を記載します。
既存ファイルがある場合は、その内容を残して追記してください。

```text
@AGENTS.md
```

### 3. Skillsの参照を設定する

```powershell
powershell -ExecutionPolicy Bypass -File hojou/scripts/setup-skills-link.ps1
```

このスクリプトは、利用側プロジェクトの`.claude/skills`と`.agents/skills`から、本リポジトリの`.agents/skills`へディレクトリジャンクションを作成します。
新しい環境へのclone後や、本リポジトリ側にSkillが新規追加された後にも実行してください。

同じ参照先のジャンクションが既にある場合は、そのまま終了します。
`.claude/skills`または`.agents/skills`が通常のディレクトリ・ファイルとして既に存在する場合は、上書きせずエラーになります。既存Skillsとの自動統合は行わないため、該当する場合は配置を確認してください。
処理の詳細は[setup-skills-link.ps1](scripts/setup-skills-link.ps1)を参照してください。

### 4. 最初の作業を依頼する

利用側プロジェクトのルートでClaude Codeを開始し、作りたいシステムと着手する工程を伝えます。
例えば、新規開発なら次のように依頼できます。

```text
AGENTS.mdと参照先の開発プロセスに従い、要件定義工程から開始してください。
作りたいシステムは、社内の備品貸出を管理するWebアプリです。
不明点を確認しながら、作業管理と要件定義書を整備してください。
```

最初の作業では、[AIエージェント指示書](AIエージェント指示書.md)と該当工程のSkillが参照されていることを確認してください。
成果物は利用側プロジェクトに作成し、本サブモジュール内には保存しません。

## 任意設定：git/gh操作の確認ルール

Claude Codeの`.claude/settings.json`に、git/ghコマンド用の`permissions.ask`ルールを追加できます。

```powershell
powershell -ExecutionPolicy Bypass -File hojou/scripts/setup-git-safety-settings.ps1
```

既存設定を読み込み、未登録のルールを追加して保存するスクリプトです。
すべての実行モード・設定で確認プロンプトが表示されることを保証するものではありません。導入後は、使用する環境と実行モードで意図した確認が行われるか確認してください。
詳細は[setup-git-safety-settings.ps1](scripts/setup-git-safety-settings.ps1)と[Claude Codeの権限ドキュメント](https://code.claude.com/docs/en/permissions)を参照してください。

## 更新方法

利用側プロジェクトで、取り込む変更を確認したうえでサブモジュールを更新します。

```powershell
git submodule update --remote hojou
git diff --submodule
```

変更内容を確認後、利用側プロジェクトでサブモジュールの参照コミットを記録してください。
Skill構成を更新した場合は、Skill設定スクリプトも再実行します。
本リポジトリへの変更は、利用側プロジェクトへ自動では反映されません。

## リポジトリ構成

```text
AIエージェント指示書.md   … AIエージェント向けの入口（利用側のAGENTS.mdから@参照）
運用ルール/               … 開発の進め方を定めるルールとテンプレート
  開発ルール/             … 常時・状況に応じて参照する開発ルール（セキュリティ・ヘッダーブロック・バージョン管理・レビュー工程）とレビュー指摘表テンプレート（テンプレート/）
  GitHubルール/           … GitHubでIssue・ブランチ・コミットを扱う場合に参照するルール
  作業管理ルール/         … バックログ・タスクの管理ルールとテンプレート
  引継書ルール/           … 引継ぎ資料（機能別・タスク毎）の作成・更新ルールとテンプレート
.agents/skills/           … 工程・ツールごとのSkills（実体はここ、利用側の.claude/skills・.agents/skillsはこれを指すジャンクション）
scripts/
  setup-skills-link.ps1              … Skill参照設定スクリプト（上記「導入手順」参照）
  setup-git-safety-settings.ps1      … git操作安全設定の導入スクリプト（上記「任意設定」参照）
変更依頼/                … 依頼方法・対応履歴
LICENSE                  … ライセンス
```

## 不具合報告・改善提案

- 不具合や改善提案は[GitHub Issues](https://github.com/ku-kaname/hojou/issues)へお寄せください。
- 依頼の書式は[依頼ルール](変更依頼/依頼ルール.md)、対応結果は[変更履歴・非採用一覧](変更依頼/変更履歴・非採用一覧.md)にまとめています。

- 公式リポジトリへの変更は開発元プロジェクトが行います。
- 本フレームワークを参照する利用側プロジェクトのAIエージェントは、サブモジュール内を直接変更せず、Issueで依頼する運用としています。

## ライセンス

[MIT License](LICENSE)

Copyright (c) 2026 ku-kaname
