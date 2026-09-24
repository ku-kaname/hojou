# 単体テスト チェックリスト（pytest）

## フィクスチャ管理

- [ ] テスト共通処理（フィクスチャ等）は `conftest.py` に集約しているか

## unittest.mock

- [ ] `assert_called_once()` / `assert_not_called()` でモックの呼び出し有無を確認するテストを作成した場合、対称となる逆ケースにも同様のアサーションを追加しているか
