
# クラスのdocコメント
以下のみを記載し、余計な文言は記載しない
- クラス論理名（和名）
- クラス概要
- 属性

以下参照
```java
public class ExcelSumifTool {

    /**
     * Excel SUMIF自動化処理クラス
     *
     * 【概要】
     * Excelファイルの条件付き合計処理を自動化
     *
     * 【属性】
     * - data (DataFrame): 読み込んだデータ
     * - result (DataFrame): 処理結果
     */
}
```
インスタンス状態（属性）を持たないクラスの場合は、【属性】の項目自体を記載しない。

# メソッドのdocコメント
- メソッドをパターンごとにグループ分けしている場合、メソッドの外にコメントを記載する
- 処理記述書に従い、以下のみ記載する
    - メソッド論理名（和名）
    - 処理記述書格納パス
    - 【処理概要】
    - 【パラメータ】
    - 【戻り値】
    - 【例外処理】
    - 【処理フロー】
- 余計な文言は記載しない。
- クラスの有無によってこの書式は変わらない。

以下参照
```java
public class Main {

    /**
     * ==================================================
     * ユーザー操作
     * - createUserEndpoint : ユーザー作成
     * - updateUserEndpoint : ユーザー情報更新
     * - deleteUserEndpoint : ユーザー削除
     * - getUserEndpoint : ユーザー情報取得
     * - getAllUserEndpoint : 全ユーザー情報取得
     *
     * 設計書：review-scheduler\設計書\サーバー処理（main）\ユーザー操作
     * ==================================================
     */

    public UserResponse createUserEndpoint() { }

    public UserResponse updateUserEndpoint() { }


    /**
     * ==================================================
     * 復習項目操作
     * - createReviewEndpoint : 復習項目作成
     * - updateReviewEndpoint : 復習項目更新
     * - deleteReviewEndpoint : 復習項目削除
     * - getReviewsEndpoint : 復習項目取得
     *
     * 設計書：review-scheduler\設計書\サーバー処理（main）\復習項目操作
     * ==================================================
     */

    /**
     * 復習項目更新
     *
     * 設計書：review-scheduler\設計書\サーバー処理（main）\復習項目操作\復習項目更新.md
     *
     * 【処理概要】
     * - 登録済み復習情報と復習管理情報に対して、ユーザーが入力した情報でテーブルを更新する。
     *
     * 【パラメータ】
     * - reviewUpdateRequest (ReviewUpdateRequest) : 復習情報更新リクエスト (必須)
     * - auth (UserValidationResponse) : 有効ユーザー検証結果 (必須)
     * - db (Session) : データベース (必須)
     *
     * 【戻り値】
     * - reviewUpdateResponseList (List<ReviewUpdateResponse>) : 復習情報更新レスポンスリスト
     *
     * 【例外処理】
     * - ResponseStatusException(422) : reviewId が未入力（必須項目）または範囲外（1〜999）の場合
     * - ResponseStatusException(404) : 復習項目が取得できない場合
     *
     * 【処理フロー】
     * 1. 入力値チェック
     * 2. 現在日時取得
     * 3. 復習情報更新
     * 4. 復習管理情報更新
     * 5. 戻り値を設定
     */
    @PatchMapping("/users/{userId}/reviews/{reviewId}")
    public List<ReviewUpdateResponse> updateReviewEndpoint(
            @RequestBody ReviewUpdateRequest reviewUpdateRequest,
            @AuthenticationPrincipal UserValidationResponse auth,
            Session db
    ) {

        // 1. 入力値チェック
        // 復習項目、復習内容詳細、復習回、対応済みフラグのいずれも設定されていない
        if ((reviewUpdateRequest.getReviewItem() == null || reviewUpdateRequest.getReviewItem().isEmpty())
                && (reviewUpdateRequest.getDescription() == null || reviewUpdateRequest.getDescription().isEmpty())
                && reviewUpdateRequest.getReviewTime() == null && reviewUpdateRequest.getDoneFlag() == null) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "復習項目、復習内容詳細、復習回のいずれかに入力必須です。");
        }
        // 復習回が設定され、対応済みフラグが未設定
        if (reviewUpdateRequest.getReviewTime() != null && reviewUpdateRequest.getDoneFlag() == null) {
            throw new ResponseStatusException(HttpStatus.UNPROCESSABLE_ENTITY, "復習回を指定する場合、対応状況も指定してください。");
        }

        // 2. 現在日時取得
        OffsetDateTime today = OffsetDateTime.now(ZoneOffset.UTC);

        // 3. 復習情報更新
        // 3.(1) 復習項目、復習内容詳細のいずれかが設定されている場合、メソッド呼び出し
        Review updatedReview = null;
        if ((reviewUpdateRequest.getReviewItem() != null && !reviewUpdateRequest.getReviewItem().isEmpty())
                || (reviewUpdateRequest.getDescription() != null && !reviewUpdateRequest.getDescription().isEmpty())) {
            updatedReview = updateReview(
                    db,
                    auth.getUserId(),
                    reviewUpdateRequest.getReviewId(),
                    today,
                    reviewUpdateRequest.getReviewItem(),
                    reviewUpdateRequest.getDescription()
            );
            // 3.(2) 例外処理
            if (updatedReview == null) {
                throw new ResponseStatusException(HttpStatus.NOT_FOUND, "対象の復習項目が見つかりませんでした");
            }
        }

        // 4. 復習管理情報更新
        // 4.(1) 復習回、対応済みフラグが設定されている場合、以下メソッド呼び出し
        List<ReviewManagement> updatedReviewManagementList = new ArrayList<>();
        boolean updateReviewManagementFlag = false;
        if (reviewUpdateRequest.getReviewTime() != null && reviewUpdateRequest.getDoneFlag() != null) {
            updatedReviewManagementList = updateReviewManagement(
                    db,
                    auth.getUserId(),
                    reviewUpdateRequest.getReviewId(),
                    reviewUpdateRequest.getReviewTime(),
                    reviewUpdateRequest.getDoneFlag(),
                    today
            );
            updateReviewManagementFlag = true;
        }

        // 4.(2) 復習回が未設定、対応済みフラグが設定されている場合、以下メソッド呼び出し
        boolean updateAllReviewManagementFlag = false;
        if (reviewUpdateRequest.getReviewTime() == null && reviewUpdateRequest.getDoneFlag() != null) {
            updatedReviewManagementList = updateAllReviewManagement(
                    db,
                    auth.getUserId(),
                    reviewUpdateRequest.getReviewId(),
                    reviewUpdateRequest.getDoneFlag(),
                    today
            );
            updateAllReviewManagementFlag = true;
        }

        // 4.(3) 例外処理
        if ((updateReviewManagementFlag || updateAllReviewManagementFlag) && updatedReviewManagementList.isEmpty()) {
            throw new ResponseStatusException(HttpStatus.NOT_FOUND, "対象の復習項目が見つかりませんでした");
        }

        db.commit();
        if (updatedReview != null) {
            db.refresh(updatedReview);
        }
        if (updateReviewManagementFlag || updateAllReviewManagementFlag) {
            for (ReviewManagement updatedReviewManagement : updatedReviewManagementList) {
                db.refresh(updatedReviewManagement);
            }
        }

        // 5. 戻り値を設定
        List<ReviewScheduleWithDoneFlag> scheduleList = new ArrayList<>();
        for (ReviewManagement updatedReviewManagement : updatedReviewManagementList) {
            scheduleList.add(new ReviewScheduleWithDoneFlag(
                    updatedReviewManagement.getReviewTime(),
                    updatedReviewManagement.getReviewDate(),
                    updatedReviewManagement.getDoneFlag() ? "済" : "未済"
            ));
        }
        return List.of(new ReviewUpdateResponse(
                updatedReview != null ? updatedReview.getReviewItem() : null,
                updatedReview != null ? updatedReview.getDescription() : null,
                scheduleList
        ));
    }
}
```