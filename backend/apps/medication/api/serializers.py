from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from rest_framework import serializers


class CreateMedicationPlanSerializer(serializers.Serializer):
    workflow_draft_id = serializers.UUIDField(required=False)
    medicine_id = serializers.UUIDField()
    dosage_text = serializers.CharField(max_length=200, trim_whitespace=True)
    timezone = serializers.CharField(max_length=64)
    times = serializers.ListField(
        child=serializers.RegexField(r"^(?:[01][0-9]|2[0-3]):[0-5][0-9]$"),
        allow_empty=False,
        max_length=24,
    )

    def validate(self, attrs):
        if isinstance(self.initial_data, dict):
            unknown = set(self.initial_data) - set(self.fields)
            if unknown:
                raise serializers.ValidationError(
                    {key: "不支持该字段。" for key in sorted(unknown)}
                )
        if attrs["dosage_text"] == "":
            raise serializers.ValidationError({"dosage_text": "用量不能为空。"})
        if len(attrs["times"]) != len(set(attrs["times"])):
            raise serializers.ValidationError({"times": "每日时刻不能重复。"})
        try:
            ZoneInfo(attrs["timezone"])
        except (ZoneInfoNotFoundError, ValueError) as exc:
            raise serializers.ValidationError({"timezone": "时区必须是有效的 IANA 时区。"}) from exc
        return attrs


class MedicationOccurrenceActionSerializer(serializers.Serializer):
    action = serializers.ChoiceField(choices=("taken", "skipped"))

    def validate(self, attrs):
        if isinstance(self.initial_data, dict):
            unknown = set(self.initial_data) - set(self.fields)
            if unknown:
                raise serializers.ValidationError(
                    {key: "不支持该字段。" for key in sorted(unknown)}
                )
        return attrs
