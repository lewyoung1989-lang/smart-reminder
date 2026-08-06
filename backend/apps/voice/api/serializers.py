from django.conf import settings
from rest_framework import serializers


class VoiceTranscriptionSerializer(serializers.Serializer):
    audio = serializers.FileField(required=True, allow_empty_file=False)

    def validate_audio(self, audio):
        if audio.size > settings.ASR_MAX_AUDIO_BYTES:
            raise serializers.ValidationError(
                "audio_too_large",
                code="audio_too_large",
            )
        return audio
