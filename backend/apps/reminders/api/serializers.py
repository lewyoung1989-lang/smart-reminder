from rest_framework import serializers


class CreateVoiceReminderDraftSerializer(serializers.Serializer):
    transcript = serializers.CharField(
        allow_blank=False,
        max_length=500,
        trim_whitespace=True,
    )


class CreateTextReminderDraftSerializer(serializers.Serializer):
    text = serializers.CharField(
        allow_blank=False,
        max_length=500,
        trim_whitespace=True,
    )
