from datetime import datetime

from apps.workflows.services.task_parser import WorkflowTaskParser


NOW = datetime(2026, 8, 8, 10, 30, tzinfo=None)
TIMEZONE = "Asia/Shanghai"


def parse(text: str):
    return WorkflowTaskParser().parse(text, now=NOW, timezone=TIMEZONE)


def test_parses_complete_medication_schedule():
    task = parse("每天早上八点吃阿莫西林 0.5g")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "阿莫西林",
        "dose_text": "0.5g",
        "frequency": "daily",
    }
    assert task.requested_capabilities == [
        "medicine.schedule",
        "notification.important",
    ]
    assert task.ambiguities == []


def test_parses_medication_when_dose_immediately_follows_the_name():
    task = parse("每天服药阿莫西林0.5g")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "阿莫西林",
        "dose_text": "0.5g",
        "frequency": "daily",
    }


def test_parses_expiry_task_with_explicit_medicine_id():
    task = parse("药品 med-42 有效期提前30天提醒我")

    assert task.template_hint == "medicine_expiry"
    assert task.slots == {"medicine_id": "med-42", "threshold_days": 30}
    assert task.requested_capabilities == [
        "medicine.inventory",
        "notification.important",
    ]
    assert task.ambiguities == []


def test_parses_tomorrow_public_transit_departure():
    task = parse("明天八点到虹桥火车站，坐公交出门")

    assert task.template_hint == "smart_departure"
    assert task.slots == {
        "arrival_time": "2026-08-09T08:00:00+08:00",
        "destination_text": "虹桥火车站",
        "travel_mode": "public_transit",
    }
    assert task.requested_capabilities == [
        "route.estimate",
        "weather.forecast",
        "notification.important",
    ]
    assert task.ambiguities == []


def test_returns_clarification_when_medication_dose_is_missing():
    task = parse("每天吃阿莫西林")

    assert task.template_hint is None
    assert task.slots == {}
    assert task.ambiguities == ["请补充药品剂量和服药周期"]


def test_returns_clarification_when_expiry_medicine_id_is_missing():
    task = parse("提醒我检查有效期")

    assert task.template_hint is None
    assert task.slots == {}
    assert task.ambiguities == ["请提供明确的药品ID"]


def test_unknown_text_returns_a_single_chinese_question_without_slots():
    task = parse("帮我安排一下")

    assert task.template_hint is None
    assert task.slots == {}
    assert task.ambiguities == ["请说明要创建哪种提醒"]


def test_url_is_not_copied_into_slots():
    task = parse("明天八点去https://example.com，坐公交出门")

    assert task.template_hint is None
    assert task.slots == {}
    assert task.ambiguities == ["目的地不能包含网址，请提供地点名称"]
    assert "https://" not in task.model_dump_json()


def test_url_in_medication_request_is_not_copied_into_slots():
    task = parse("每天吃药https://example.com 0.5g")

    assert task.template_hint is None
    assert task.slots == {}
    assert task.ambiguities == ["请勿在请求中包含网址"]
    assert "https://" not in task.model_dump_json()


def test_non_http_url_scheme_is_not_copied_into_slots():
    task = parse("每天吃药FTP://example.com 0.5g")

    assert task.template_hint is None
    assert task.slots == {}
    assert task.ambiguities == ["请勿在请求中包含网址"]
    assert "example.com" not in task.model_dump_json()


def test_invalid_chinese_time_returns_clarification_instead_of_raising():
    task = parse("明天一两点到虹桥火车站，坐公交出门")

    assert task.template_hint is None
    assert task.slots == {}
    assert task.ambiguities == ["请补充到达时间、目的地和出行方式"]


def test_compact_departure_request_stops_destination_before_travel_mode():
    task = parse("明天八点到虹桥火车站坐公交出门")

    assert task.template_hint == "smart_departure"
    assert task.slots["destination_text"] == "虹桥火车站"
    assert task.slots["travel_mode"] == "public_transit"


def test_tomorrow_morning_phrase_is_parsed_as_tomorrow():
    task = parse("明早八点到虹桥火车站，坐公交出门")

    assert task.template_hint == "smart_departure"
    assert task.slots["arrival_time"] == "2026-08-09T08:00:00+08:00"
