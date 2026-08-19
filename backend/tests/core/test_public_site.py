from django.test import override_settings


PUBLIC_SITE_SETTINGS = {
    "SITE_NAME": "智能提醒",
    "SITE_OWNER_NAME": "测试备案主体",
    "SITE_CONTACT_EMAIL": "support@example.com",
    "ICP_FILING_NUMBER": "粤ICP备12345678号-1",
}


@override_settings(**PUBLIC_SITE_SETTINGS)
def test_home_presents_product_and_required_filing_information(client):
    response = client.get("/")
    content = response.content.decode()

    assert response.status_code == 200
    assert "智能提醒" in content
    assert "日常提醒" in content
    assert "家庭药箱" in content
    assert "拍照录入" in content
    assert "测试备案主体" in content
    assert "support@example.com" in content
    assert "粤ICP备12345678号-1" in content
    assert 'href="https://beian.miit.gov.cn/"' in content
    assert "beian.mps.gov.cn" not in content


@override_settings(
    **PUBLIC_SITE_SETTINGS,
    PUBLIC_SECURITY_FILING_NUMBER="粤公网安备44030002000001号",
    PUBLIC_SECURITY_RECORD_CODE="44030002000001",
)
def test_home_links_public_security_filing_when_configured(client):
    content = client.get("/").content.decode()

    assert "粤公网安备44030002000001号" in content
    assert "beian.mps.gov.cn/#/query/webSearch?code=44030002000001" in content


@override_settings(**PUBLIC_SITE_SETTINGS)
def test_privacy_policy_explains_actual_data_boundaries(client):
    response = client.get("/privacy/")
    content = response.content.decode()

    assert response.status_code == 200
    assert "手机号码" in content
    assert "DeepSeek" in content
    assert "药盒原图不会因此发送给大模型" in content
    assert "24 小时" in content
    assert "support@example.com" in content


@override_settings(**PUBLIC_SITE_SETTINGS)
def test_terms_explain_ocr_and_medicine_safety_boundary(client):
    response = client.get("/terms/")
    content = response.content.decode()

    assert response.status_code == 200
    assert "OCR 和大模型输出可能不准确" in content
    assert "不构成诊断、处方、用药建议" in content
    assert 'href="/privacy/"' in content
