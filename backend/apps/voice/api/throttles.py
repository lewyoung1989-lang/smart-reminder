from rest_framework.throttling import SimpleRateThrottle, UserRateThrottle


class VoiceTranscriptionUserThrottle(UserRateThrottle):
    scope = "voice_transcription_user"


class VoiceTranscriptionIpThrottle(SimpleRateThrottle):
    scope = "voice_transcription_ip"

    def get_cache_key(self, request, view):
        ident = self.get_ident(request)
        return self.cache_format % {"scope": self.scope, "ident": ident}
