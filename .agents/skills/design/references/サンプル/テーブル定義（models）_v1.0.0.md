# テーブル定義

- **工程**: 設計工程
- **作成者**: ku-kaname
- **作成日**: 2026-06-30
- **最終更新日**: 2026-09-23

---

## USER

| 項目 | 内容 |
|---|---|
| テーブル論理名 | ユーザー情報 |
| テーブル物理名 | USER |

### 説明

アプリケーションの利用者情報を管理する。

| 論理名 | 物理名 | 型 | 必須 | 最小値 | 最大値 | 最小桁 | 最大桁 | 主キー | 外部キー | 制約 | インデックス | 備考 |
|---|---|---|:---:|---:|---:|---:|---:|:---:|---|---|---|---|
| ユーザーID | id | INTEGER | ○ | - | - | - | - | ○ | - | - | - | 自動採番 |
| ユーザー名 | user_name | VARCHAR | ○ | - | - | 1 | 50 | - | - | uq_user_user_name | - | - |
| ハッシュ済みパスワード | hashed_password | VARCHAR | ○ | - | - | 1 | 255 | - | - | - | - | - |
| 削除済みフラグ | delete_flag | BOOLEAN | ○ | - | - | - | - | - | - | - | - | - |
| 管理者フラグ | admin_flag | BOOLEAN | ○ | - | - | - | - | - | - | - | - | - |
| 作成日 | created_at | DATETIME | ○ | - | - | - | - | - | - | - | - | - |
| 更新日 | updated_at | DATETIME | ○ | - | - | - | - | - | - | - | - | 更新しない限り作成日と同じ値 |

### 補足

- なし

---

## REVIEW

| 項目 | 内容 |
|---|---|
| テーブル論理名 | 復習情報 |
| テーブル物理名 | REVIEW |

### 説明

ユーザーが登録した復習対象の項目を管理する。

| 論理名 | 物理名 | 型 | 必須 | 最小値 | 最大値 | 最小桁 | 最大桁 | 主キー | 外部キー | 制約 | インデックス | 備考 |
|---|---|---|:---:|---:|---:|---:|---:|:---:|---|---|---|---|
| ユーザーID | user_id | INTEGER | ○ | - | - | - | - | ○ | `foreign_key.constraint_name`: fk_review_user_id<br>参照先: USER.id<br>ON UPDATE: CASCADE / ON DELETE: CASCADE<br>カーディナリティ: 多:1 | - | - | - |
| 復習項目ID | review_id | INTEGER | ○ | - | - | 1 | 3 | ○ | - | - | - | ユーザーごとにIDを割り振る<br>1人当たり999件まで |
| 復習項目 | review_item | VARCHAR | ○ | - | - | 1 | 200 | - | - | - | - | - |
| 復習内容詳細 | description | VARCHAR | - | - | - | 1 | 1000 | - | - | - | - | - |
| 学習日 | study_date | DATETIME | ○ | - | - | - | - | - | - | - | - | - |
| 作成日 | created_at | DATETIME | ○ | - | - | - | - | - | - | - | - | - |
| 更新日 | updated_at | DATETIME | ○ | - | - | - | - | - | - | - | - | 更新しない限り作成日と同じ値 |

### 補足

- なし

---

## REVIEW_MANAGEMENT

| 項目 | 内容 |
|---|---|
| テーブル論理名 | 復習管理情報 |
| テーブル物理名 | REVIEW_MANAGEMENT |

### 説明

復習項目ごとの復習スケジュール（各回の復習予定日・対応状況）を管理する。

| 論理名 | 物理名 | 型 | 必須 | 最小値 | 最大値 | 最小桁 | 最大桁 | 主キー | 外部キー | 制約 | インデックス | 備考 |
|---|---|---|:---:|---:|---:|---:|---:|:---:|---|---|---|---|
| ユーザーID | user_id | INTEGER | ○ | - | - | - | - | ○ | `foreign_key.constraint_name`: fk_review_management_user_id<br>参照先: USER.id<br>ON UPDATE: CASCADE / ON DELETE: CASCADE<br>カーディナリティ: 多:1 | - | - | - |
| 復習項目ID | review_id | INTEGER | ○ | - | - | 1 | 3 | ○ | `foreign_key.constraint_name`: fk_review_management_review_id<br>参照先: REVIEW.review_id<br>ON UPDATE: CASCADE / ON DELETE: CASCADE<br>カーディナリティ: 多:1 | - | - | - |
| 復習回 | review_time | INTEGER | ○ | - | - | 1 | 1 | ○ | - | - | - | 1つのreview_id毎に1～5 |
| 復習予定日 | review_date | DATETIME | ○ | - | - | - | - | - | - | - | - | 学習日+1,+3,+7,+15,+31日 |
| 対応済みフラグ | done_flag | BOOLEAN | ○ | - | - | - | - | - | - | - | - | - |
| 作成日 | created_at | DATETIME | ○ | - | - | - | - | - | - | - | - | - |
| 更新日 | updated_at | DATETIME | ○ | - | - | - | - | - | - | - | - | 更新しない限り作成日と同じ値 |

### 補足

- なし
