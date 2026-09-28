# 作業ログの自動記録（worklog-hook.ps1・worklog-record.ps1）で共通に使う処理。
# 両スクリプトから読み込んで（ドットソースで）使い、単独では実行しない。
#
# 記録途中の作業区間は、セッションごとに一時フォルダ（%TEMP%\hojou-worklog\<セッションID>.json）へ
# {open: 開いている作業区間の開始, last: 最後にhookが動いた時刻, segments: 終了した作業区間}の形で保存する。
# 時刻はいずれもローカル時刻のyyyy-MM-ddTHH:mm:ss。
#
# テスト用に、環境変数HOJOU_WORKLOG_NOW（yyyy-MM-ddTHH:mm:ss）で現在時刻を指定できる。

$timeFormat = "yyyy-MM-ddTHH:mm:ss"
$sessionIdPattern = '^[A-Za-z0-9_-]+$'
$stateRetentionDays = 30
$utf8 = New-Object System.Text.UTF8Encoding($false)
$invariantCulture = [System.Globalization.CultureInfo]::InvariantCulture

function ConvertTo-Time([string]$text, [string]$format) {
    return [DateTime]::ParseExact($text, $format, $invariantCulture)
}

function Get-NowText {
    if (-not [string]::IsNullOrEmpty($env:HOJOU_WORKLOG_NOW)) {
        $now = ConvertTo-Time $env:HOJOU_WORKLOG_NOW $timeFormat
    } else {
        $now = Get-Date
    }
    return $now.ToString($timeFormat, $invariantCulture)
}

function Get-StateDir {
    $tempRoot = [System.IO.Path]::GetTempPath()
    return (Join-Path $tempRoot "hojou-worklog")
}

# セッションIDは一時ファイル名に使うため、英数字・ハイフン・アンダースコアのみを受け付ける
function Get-StatePath([string]$sessionId) {
    if ($sessionId -notmatch $sessionIdPattern) {
        return $null
    }
    return (Join-Path (Get-StateDir) ($sessionId + ".json"))
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
    if (-not (Test-Path -LiteralPath $stateDir)) {
        return
    }
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

# 文字コードの設定に左右されないよう、UTF-8のバイト列で標準出力・標準エラー出力へ書き込む
function Write-Utf8Stream([System.IO.Stream]$stream, [string]$text) {
    $bytes = $utf8.GetBytes($text + "`n")
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush()
}

function Write-Utf8Output([string]$text) {
    Write-Utf8Stream ([Console]::OpenStandardOutput()) $text
}

function Write-Utf8Error([string]$text) {
    Write-Utf8Stream ([Console]::OpenStandardError()) $text
}
