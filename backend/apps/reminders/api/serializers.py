from rest_framework import serializers

from apps.reminders.models import ReminderRule


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


class ReminderRuleSerializer(serializers.ModelSerializer):
    status = serializers.SerializerMethodField()

    class Meta:
        model = ReminderRule
        fields = (
            "id",
            "title",
            "timezone",
            "scheduled_at",
            "severity",
            "status",
            "cancelled_at",
        )

    def get_status(self, rule):
        if not rule.enabled and rule.cancelled_at is not None:
            return "cancelled"
        if rule.scheduled_at <= self.context["now"]:
            return "expired"
        return "pending"
