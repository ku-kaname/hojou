# 実装 チェックリスト（SQLAlchemy）

## クエリ構築

- [ ] `select()` で JOIN する場合、全モデルを指定しているか（例：`select(A, B)` のように複数モデルを列挙する）

## バージョン・非推奨対応

- [ ] 非推奨のモジュールを使っていないか（例：`sqlalchemy.ext.declarative` は非推奨 → `sqlalchemy.orm` を使う）
