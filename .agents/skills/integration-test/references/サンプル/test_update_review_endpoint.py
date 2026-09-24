"""
==================================================
復習項目更新
テスト対象ファイル：main.py
テスト対象クラス：-
テスト対象メソッド：update_review_endpoint
テスト仕様書：test_specification/integration_test_specification/復習項目操作/復習項目更新_結合テスト仕様書.md
==================================================
"""


def _create_review(client, token, review_item="テスト復習項目"):
    return client.post(
        "/users/1/reviews",
        json={"review_item": review_item},
        headers={"Authorization": f"Bearer {token}"},
    )


"""
===結合テストNo.1===
復習項目名を更新した場合、HTTP 200 と更新後の review_item が返却されること
"""
def test_update_review_endpoint_001_update_review_item(client, make_token):
    token = make_token("testuser", "testpass")
    _create_review(client, token)

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1, "review_item": "更新後の項目名"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    body = response.json()
    assert body[0]["review_item"] == "更新後の項目名"


"""
===結合テストNo.2===
特定復習回の対応状況を更新した場合、HTTP 200 と該当復習回の done_status が "済" で返却されること
"""
def test_update_review_endpoint_002_update_specific_done_flag(client, make_token):
    token = make_token("testuser", "testpass")
    _create_review(client, token)

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1, "review_time": 1, "done_flag": True},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    schedules = response.json()[0]["review_schedule_with_done_flag_list"]
    assert len(schedules) == 1
    assert schedules[0]["review_time"] == 1
    assert schedules[0]["done_status"] == "済"


"""
===結合テストNo.3===
全復習回の対応状況を一括更新した場合、HTTP 200 と全復習回の done_status が "済" で返却されること
"""
def test_update_review_endpoint_003_update_all_done_flags(client, make_token):
    token = make_token("testuser", "testpass")
    _create_review(client, token)

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1, "done_flag": True},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    schedules = response.json()[0]["review_schedule_with_done_flag_list"]
    assert len(schedules) == 5
    for schedule in schedules:
        assert schedule["done_status"] == "済"


"""
===結合テストNo.4===
全更新項目が未入力の場合、HTTP 422 とエラーメッセージが返却されること
"""
def test_update_review_endpoint_004_no_update_fields(client, make_token):
    token = make_token("testuser", "testpass")

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "復習項目、復習内容詳細、復習回のいずれかに入力必須です。"}


"""
===結合テストNo.5===
review_time のみ指定（done_flag 未指定）の場合、HTTP 422 とエラーメッセージが返却されること
"""
def test_update_review_endpoint_005_review_time_without_done_flag(client, make_token):
    token = make_token("testuser", "testpass")

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1, "review_time": 1},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 422
    assert response.json() == {"detail": "復習回を指定する場合、対応状況も指定してください。"}


"""
===結合テストNo.6===
review_id が上限（999）を超えた値を指定した場合、HTTP 422 が返却されること
"""
def test_update_review_endpoint_006_review_id_exceeds_limit(client, make_token):
    token = make_token("testuser", "testpass")

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1000, "review_item": "更新"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 422


"""
===結合テストNo.7===
review_id が未入力の場合、HTTP 422 が返却されること
"""
def test_update_review_endpoint_007_missing_review_id(client, make_token):
    token = make_token("testuser", "testpass")

    response = client.patch(
        "/users/1/reviews/1",
        json={},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 422


"""
===結合テストNo.8===
ログイン後に管理者によって削除されたユーザーが有効期限内のトークンで PATCH した場合、HTTP 401 が返却されること
"""
def test_update_review_endpoint_008_deleted_user(client, make_token, monkeypatch):
    monkeypatch.setenv("ADMIN_SECRET_KEY_NAME", "admin")
    monkeypatch.setenv("ADMIN_SECRET_KEY_PASSWORD", "adminpass")

    token = make_token("testuser", "testpass")
    _create_review(client, token)

    admin_token = make_token("admin", "adminpass")
    client.delete("/users/1", headers={"Authorization": f"Bearer {admin_token}"})

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1, "review_item": "更新"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 401


"""
===結合テストNo.9===
存在しない review_id を指定した場合、HTTP 404 が返却されること
"""
def test_update_review_endpoint_009_nonexistent_review(client, make_token):
    token = make_token("testuser", "testpass")

    response = client.patch(
        "/users/1/reviews/99",
        json={"review_id": 99, "review_item": "更新"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 404
    assert response.json() == {"detail": "対象の復習項目が見つかりませんでした"}


"""
===結合テストNo.10===
URL の review_id とボディの review_id が異なる場合、ボディの review_id が優先されること
"""
def test_update_review_endpoint_010_body_review_id_takes_priority(client, make_token):
    token = make_token("testuser", "testpass")
    _create_review(client, token)

    response = client.patch(
        "/users/1/reviews/2",
        json={"review_id": 1, "review_item": "ボディ優先の更新"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    assert response.json()[0]["review_item"] == "ボディ優先の更新"


"""
===結合テストNo.11===
復習内容詳細を更新した場合、HTTP 200 と更新後の description が返却されること
"""
def test_update_review_endpoint_011_update_description(client, make_token):
    token = make_token("testuser", "testpass")
    _create_review(client, token)

    response = client.patch(
        "/users/1/reviews/1",
        json={"review_id": 1, "description": "更新後の詳細"},
        headers={"Authorization": f"Bearer {token}"},
    )

    assert response.status_code == 200
    assert response.json()[0]["description"] == "更新後の詳細"
