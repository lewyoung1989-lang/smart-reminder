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
        "time_of_day": "08:00",
    }
    assert task.requested_capabilities == [
        "medicine.schedule",
        "notification.important",
    ]
    assert task.ambiguities == []


def test_parses_three_daily_medication_times_without_brand_hardcoding():
    task = parse("每天早上8点、中午1点、晚上8点吃拜新同1片")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "拜新同",
        "dose_text": "1片",
        "frequency": "daily",
        "time_of_day": "08:00",
        "times": ["08:00", "13:00", "20:00"],
    }
    assert task.ambiguities == []


def test_parses_three_colon_formatted_daily_medication_times():
    task = parse("每天3次，08:00、13:00、20:00吃拜新同1片")

    assert task.slots["times"] == ["08:00", "13:00", "20:00"]
    assert task.ambiguities == []


def test_asks_for_exact_times_when_only_daily_dose_count_is_given():
    task = parse("每天3次吃拜新同1片")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "拜新同",
        "dose_text": "1片",
        "frequency": "daily",
    }
    assert task.ambiguities == ["请补充每天 3 次的具体服药时间"]


def test_asks_for_all_times_when_daily_count_and_times_do_not_match():
    task = parse("每天3次，早上8点、晚上8点吃拜新同1片")

    assert task.slots["times"] == ["08:00", "20:00"]
    assert task.ambiguities == ["请补充每天 3 次的具体服药时间"]


def test_leading_brand_name_is_not_confused_with_daily_count():
    task = parse("拜新同一天吃三次，每次一片")

    assert task.slots["medicine_name"] == "拜新同"
    assert task.slots["dose_text"] == "一片"
    assert task.ambiguities == ["请补充每天 3 次的具体服药时间"]


def test_extracts_name_after_generic_three_times_medicine_phrase():
    task = parse("我每天吃三次药，伐昔洛韦，7点，下午2点，晚上9点")

    assert task.template_hint == "medication_cycle"
    assert task.slots["medicine_name"] == "伐昔洛韦"
    assert task.slots["times"] == ["07:00", "14:00", "21:00"]
    assert task.ambiguities == ["请补充药品剂量和服药周期"]


def test_parses_medication_when_dose_immediately_follows_the_name():
    task = parse("每天早上八点服药阿莫西林0.5g")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "阿莫西林",
        "dose_text": "0.5g",
        "frequency": "daily",
        "time_of_day": "08:00",
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

    assert task.template_hint == "medication_cycle"
    assert task.slots == {"medicine_name": "阿莫西林", "frequency": "daily"}
    assert task.ambiguities == ["请补充药品剂量和服药周期"]


def test_branded_medicine_without_yao_is_treated_as_medication():
    task = parse("我每天晚上10点吃布洛芬")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "布洛芬",
        "frequency": "daily",
        "time_of_day": "22:00",
    }
    assert task.ambiguities == ["请补充药品剂量和服药周期"]


def test_daily_eating_without_medicine_is_not_a_medication_workflow():
    task = parse("我每天晚上10点吃火锅")

    assert task.template_hint is None
    assert task.ambiguities == ["请说明要创建哪种提醒"]


def test_returns_clarification_when_medication_time_is_missing():
    task = parse("每天吃阿莫西林 0.5g")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "阿莫西林",
        "dose_text": "0.5g",
        "frequency": "daily",
    }
    assert task.ambiguities == ["请补充服药时间"]


def test_clarification_keeps_parsed_frequency_and_time_when_dose_is_missing():
    task = parse("以后每天9点我吃药")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {"frequency": "daily", "time_of_day": "09:00"}
    assert task.ambiguities == ["请补充药品剂量和服药周期"]


def test_generic_medicine_name_is_treated_as_missing():
    task = parse("每天早上8点吃药1片，长期服用")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "dose_text": "1片",
        "frequency": "daily",
        "time_of_day": "08:00",
    }
    assert task.ambiguities == ["请补充药品名称"]


def test_chinese_numeral_dose_is_accepted():
    task = parse("每天9点吃阿莫西林一片")

    assert task.template_hint == "medication_cycle"
    assert task.slots["dose_text"] == "一片"
    assert task.ambiguities == []


def test_bare_medicine_name_answer_is_extracted_without_a_verb():
    task = parse("以后每天9点我吃药，布洛芬缓释胶囊")

    assert task.template_hint == "medication_cycle"
    assert task.slots["medicine_name"] == "布洛芬缓释胶囊"
    assert task.ambiguities == ["请补充药品剂量和服药周期"]


def test_bare_medicine_name_with_dose_completes_the_merged_answer():
    task = parse("以后每天9点我吃药，阿莫西林1片")

    assert task.template_hint == "medication_cycle"
    assert task.slots == {
        "medicine_name": "阿莫西林",
        "dose_text": "1片",
        "frequency": "daily",
        "time_of_day": "09:00",
    }
    assert task.ambiguities == []


def test_dose_only_answer_still_asks_for_the_medicine_name():
    task = parse("以后每天9点我吃药，1片，长期服用")

    assert task.template_hint == "medication_cycle"
    assert "medicine_name" not in task.slots
    assert task.ambiguities == ["请补充药品名称"]


def test_medicine_name_ending_with_yao_is_kept_whole():
    task = parse("每天早上9点吃降压药1片，连续吃30天")

    assert task.slots["medicine_name"] == "降压药"
    assert task.ambiguities == []


def test_returns_clarification_when_expiry_medicine_id_is_missing():
    task = parse("提醒我检查有效期")

    assert task.template_hint == "medicine_expiry"
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

    assert task.template_hint == "smart_departure"
    assert task.slots == {
        "destination_text": "虹桥火车站",
        "travel_mode": "public_transit",
    }
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
