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


class CreateWorkflowDraftSerializer(serializers.Serializer):
    text = serializers.CharField(
        allow_blank=False,
        max_length=500,
        trim_whitespace=True,
    )

    def validate(self, attrs):
        unexpected_fields = set(self.initial_data) - {"text"}
        if unexpected_fields:
            raise serializers.ValidationError(
                {field: "不支持该字段" for field in unexpected_fields}
            )
        return attrs


class ConfirmWorkflowDraftSerializer(serializers.Serializer):
    def validate(self, attrs):
        if self.initial_data:
            raise serializers.ValidationError(
                {field: "不支持该字段" for field in self.initial_data}
            )
        return attrs


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
        if rule.scheduled_at is None:
            return "workflow"
        if rule.scheduled_at <= self.context["now"]:
            return "expired"
        return "pending"
