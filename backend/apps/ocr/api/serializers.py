from rest_framework import serializers


class UploadRequestSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=["front", "expiry"])
    content_type = serializers.ChoiceField(
        choices=["image/jpeg", "image/png"]
    )
    byte_length = serializers.IntegerField(min_value=1)


class JobImageSerializer(serializers.Serializer):
    kind = serializers.ChoiceField(choices=["front", "expiry"])
    object_key = serializers.CharField(max_length=300)


class CreateJobSerializer(serializers.Serializer):
    images = JobImageSerializer(many=True, min_length=1, max_length=2)

    def validate_images(self, value):
        kinds = [image["kind"] for image in value]
        if len(set(kinds)) != len(kinds) or "front" not in kinds:
            raise serializers.ValidationError(
                "正面图片必填，图片类型不能重复"
            )

        # 只接受当前用户命名空间下的临时对象键，阻止跨用户 OCR。
        user_prefix = f"ocr/tmp/{self.context['request'].user.id}/"
        if any(
            not image["object_key"].startswith(user_prefix)
            for image in value
        ):
            raise serializers.ValidationError("图片不属于当前用户")
        return value


class ConfirmCandidateSerializer(serializers.Serializer):
    scope = serializers.ChoiceField(
        choices=("personal", "family"), required=False, default="personal"
    )
    medicine_name = serializers.CharField(max_length=200)
    specification = serializers.CharField(
        max_length=120,
        allow_blank=True,
        required=False,
        default="",
    )
    manufacturer = serializers.CharField(
        max_length=200,
        allow_blank=True,
        required=False,
        default="",
    )
    retain_front_photo = serializers.BooleanField(required=False, default=True)
    batch_number = serializers.CharField(
        max_length=100,
        allow_blank=True,
        required=False,
        default="",
    )
    production_date = serializers.DateField(required=False, allow_null=True)
    expiry_date = serializers.DateField(required=False, allow_null=True)
    quantity = serializers.IntegerField(min_value=1, max_value=999, default=1)

    def validate(self, attrs):
        production_date = attrs.get("production_date")
        expiry_date = attrs.get("expiry_date")
        if (
            production_date
            and expiry_date
            and production_date > expiry_date
        ):
            raise serializers.ValidationError(
                {"expiry_date": "有效期不能早于生产日期"}
            )
        return attrs
