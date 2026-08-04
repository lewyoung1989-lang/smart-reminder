from django.core.management import call_command


def test_check_ocr_reports_line_count(mocker, capsys):
    provider = mocker.patch(
        "apps.ocr.management.commands.check_ocr.get_ocr_provider"
    ).return_value
    provider.recognize.return_value.lines = (object(),)

    call_command(
        "check_ocr",
        "backend/tests/ocr/fixtures/medicine_front.jpg",
    )

    output = capsys.readouterr().out
    assert "OCR smoke check passed: 1 lines" in output
    assert "布洛芬" not in output
