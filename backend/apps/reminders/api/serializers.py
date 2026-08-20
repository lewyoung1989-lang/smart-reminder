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


class ReminderActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=("complete", "snooze"))
    snooze_minutes = serializers.IntegerField(required=False)

    def validate(self, attrs):
        if attrs["action"] == "complete":
            if "snooze_minutes" in attrs:
                raise serializers.ValidationError(
                    {"snooze_minutes": "完成提醒时不支持该字段"}
                )
            return attrs

        minutes = attrs.get("snooze_minutes")
        if minutes not in (10, 30, 1440):
            raise serializers.ValidationError(
                {"snooze_minutes": "只能选择 10、30 或 1440 分钟"}
            )
        return attrs


class AnswerWorkflowDraftSerializer(serializers.Serializer):
    answer = serializers.CharField(
        allow_blank=False,
        max_length=500,
        trim_whitespace=True,
    )

    def validate(self, attrs):
        unexpected_fields = set(self.initial_data) - {"answer"}
        if unexpected_fields:
            raise serializers.ValidationError(
                {field: "不支持该字段" for field in unexpected_fields}
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
            "completed_at",
        )

    def get_status(self, rule):
        if rule.completed_at is not None:
            return "completed"
        if not rule.enabled and rule.cancelled_at is not None:
            return "cancelled"
        if rule.scheduled_at is None:
            return "workflow"
        if rule.scheduled_at <= self.context["now"]:
            return "expired"
        return "pending"
