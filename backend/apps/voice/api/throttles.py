from ipaddress import ip_address

from django.conf import settings
from rest_framework.throttling import SimpleRateThrottle, UserRateThrottle


class VoiceTranscriptionUserThrottle(UserRateThrottle):
    scope = "voice_transcription_user"


class VoiceTranscriptionIpThrottle(SimpleRateThrottle):
    scope = "voice_transcription_ip"

    def get_cache_key(self, request, view):
        remote_addr = request.META.get("REMOTE_ADDR") or "unknown"
        ident = remote_addr
        if remote_addr in settings.ASR_TRUSTED_PROXY_IPS:
            forwarded_for = request.META.get("HTTP_X_FORWARDED_FOR", "")
            if "," not in forwarded_for:
                try:
                    ident = str(ip_address(forwarded_for.strip()))
                except ValueError:
                    pass
        return self.cache_format % {"scope": self.scope, "ident": ident}
