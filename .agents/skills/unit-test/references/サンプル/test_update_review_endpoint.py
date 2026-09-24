from datetime import datetime, timezone

import pytest
from fastapi import HTTPException

from app.main import update_review_endpoint
from app.schemas import ReviewUpdateRequest

"""
==================================================
復習項目更新
テスト対象ファイル：main.py
テスト対象クラス：-
テスト対象メソッド：update_review_endpoint
テスト仕様書：テスト仕様書/単体テスト仕様書/サーバー処理/復習項目操作/復習項目更新_単体テスト仕様書.md
==================================================
"""

"""
===単体テストNo.2===
復習項目・復習内容詳細・復習回が全てNone（または空文字）の場合に422エラーが発生すること
"""
def test_update_review_endpoint_002_all_fields_empty(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    request = ReviewUpdateRequest(review_id=1, review_item=None, description=None, review_time=None)

    with pytest.raises(HTTPException) as exc_info:
        update_review_endpoint(request, auth, db=mocker.MagicMock())

    assert exc_info.value.status_code == 422
    assert exc_info.value.detail == "復習項目、復習内容詳細、復習回のいずれかに入力必須です。"

"""
===単体テストNo.3===
復習回が設定されているが対応済みフラグが未設定の場合に422エラーが発生すること
"""
def test_update_review_endpoint_003_review_time_without_done_flag(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    request = ReviewUpdateRequest(review_id=1, review_time=1, done_flag=None)

    with pytest.raises(HTTPException) as exc_info:
        update_review_endpoint(request, auth, db=mocker.MagicMock())

    assert exc_info.value.status_code == 422
    assert exc_info.value.detail == "復習回を指定する場合、対応状況も指定してください。"

"""
===単体テストNo.4===
復習項目のみ指定した場合、update_reviewのみ呼ばれupdate_review_managementとupdate_all_review_managementが呼ばれないこと
"""
def test_update_review_endpoint_004_review_item_only(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    updated_review = mocker.MagicMock(review_item="new_item", description=None)
    update_review_mock = mocker.patch("app.main.update_review", return_value=updated_review)
    update_review_management_mock = mocker.patch("app.main.update_review_management")
    update_all_review_management_mock = mocker.patch("app.main.update_all_review_management")
    request = ReviewUpdateRequest(review_id=1, review_item="new_item", review_time=None, done_flag=None)

    response = update_review_endpoint(request, auth, db=mocker.MagicMock())

    update_review_mock.assert_called_once()
    update_review_management_mock.assert_not_called()
    update_all_review_management_mock.assert_not_called()
    assert response[0].review_item == "new_item"

"""
===単体テストNo.5===
復習内容詳細のみ指定した場合、update_reviewのみ呼ばれupdate_review_managementとupdate_all_review_managementが呼ばれないこと
"""
def test_update_review_endpoint_005_description_only(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    updated_review = mocker.MagicMock(review_item=None, description="new_description")
    update_review_mock = mocker.patch("app.main.update_review", return_value=updated_review)
    update_review_management_mock = mocker.patch("app.main.update_review_management")
    update_all_review_management_mock = mocker.patch("app.main.update_all_review_management")
    request = ReviewUpdateRequest(review_id=1, description="new_description", review_time=None, done_flag=None)

    response = update_review_endpoint(request, auth, db=mocker.MagicMock())

    update_review_mock.assert_called_once()
    update_review_management_mock.assert_not_called()
    update_all_review_management_mock.assert_not_called()
    assert response[0].description == "new_description"

"""
===単体テストNo.6===
復習回と対応済みフラグを指定した場合、update_review_managementが呼ばれること
"""
def test_update_review_endpoint_006_review_management_update(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    review_management = mocker.MagicMock(review_time=1, review_date=datetime.now(timezone.utc), done_flag=True)
    update_review_mock = mocker.patch("app.main.update_review")
    update_review_management_mock = mocker.patch(
        "app.main.update_review_management", return_value=[review_management]
    )
    update_all_review_management_mock = mocker.patch("app.main.update_all_review_management")
    request = ReviewUpdateRequest(review_id=1, review_time=1, done_flag=True)

    response = update_review_endpoint(request, auth, db=mocker.MagicMock())

    update_review_mock.assert_not_called()
    update_review_management_mock.assert_called_once()
    update_all_review_management_mock.assert_not_called()
    assert response[0].review_schedule_with_done_flag_list[0].done_status == "済"

"""
===単体テストNo.7===
対応済みフラグのみ指定（復習回なし）した場合、update_all_review_managementが呼ばれること
"""
def test_update_review_endpoint_007_all_review_management_update(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    review_management = mocker.MagicMock(review_time=1, review_date=datetime.now(timezone.utc), done_flag=True)
    update_review_mock = mocker.patch("app.main.update_review")
    update_review_management_mock = mocker.patch("app.main.update_review_management")
    update_all_review_management_mock = mocker.patch(
        "app.main.update_all_review_management", return_value=[review_management]
    )
    request = ReviewUpdateRequest(review_id=1, review_time=None, done_flag=True)

    response = update_review_endpoint(request, auth, db=mocker.MagicMock())

    update_review_mock.assert_not_called()
    update_all_review_management_mock.assert_called_once()
    update_review_management_mock.assert_not_called()
    assert response[0].review_schedule_with_done_flag_list[0].done_status == "済"

"""
===単体テストNo.8===
update_reviewがNoneを返した場合に404エラーが発生すること
"""
def test_update_review_endpoint_008_review_not_found(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    mocker.patch("app.main.update_review", return_value=None)
    request = ReviewUpdateRequest(review_id=1, review_item="new_item")

    with pytest.raises(HTTPException) as exc_info:
        update_review_endpoint(request, auth, db=mocker.MagicMock())

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "対象の復習項目が見つかりませんでした"

"""
===単体テストNo.9===
update_review_managementが空リストを返した場合に404エラーが発生すること
"""
def test_update_review_endpoint_009_review_management_not_found(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    mocker.patch("app.main.update_review_management", return_value=[])
    request = ReviewUpdateRequest(review_id=1, review_time=1, done_flag=True)

    with pytest.raises(HTTPException) as exc_info:
        update_review_endpoint(request, auth, db=mocker.MagicMock())

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "対象の復習項目が見つかりませんでした"

"""
===単体テストNo.10===
update_all_review_managementが空リストを返した場合に404エラーが発生すること
"""
def test_update_review_endpoint_010_all_review_management_not_found(mocker, make_auth):
    auth = make_auth(delete_flag=False)
    mocker.patch("app.main.update_all_review_management", return_value=[])
    request = ReviewUpdateRequest(review_id=1, review_time=None, done_flag=True)

    with pytest.raises(HTTPException) as exc_info:
        update_review_endpoint(request, auth, db=mocker.MagicMock())

    assert exc_info.value.status_code == 404
    assert exc_info.value.detail == "対象の復習項目が見つかりませんでした"
