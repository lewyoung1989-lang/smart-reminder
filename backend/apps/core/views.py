from urllib.parse import urlencode

from django.conf import settings
from django.http import JsonResponse
from django.shortcuts import render


def _public_site_context():
    security_number = settings.PUBLIC_SECURITY_FILING_NUMBER
    security_code = settings.PUBLIC_SECURITY_RECORD_CODE
    security_url = ""
    if security_number and security_code:
        query = urlencode({"code": security_code})
        security_url = f"https://beian.mps.gov.cn/#/query/webSearch?{query}"

    return {
        "site_name": settings.SITE_NAME,
        "site_owner_name": settings.SITE_OWNER_NAME,
        "site_contact_email": settings.SITE_CONTACT_EMAIL,
        "icp_filing_number": settings.ICP_FILING_NUMBER,
        "public_security_filing_number": security_number,
        "public_security_filing_url": security_url,
    }


def home(request):
    return render(request, "public_site/home.html", _public_site_context())


def privacy(request):
    return render(request, "public_site/privacy.html", _public_site_context())


def terms(request):
    return render(request, "public_site/terms.html", _public_site_context())


def health(_request):
    return JsonResponse(
        {
            "status": "ok",
            "service": "smart-reminder-api",
        }
    )
