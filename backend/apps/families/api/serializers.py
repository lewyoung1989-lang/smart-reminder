from rest_framework import serializers


class CreateFamilySerializer(serializers.Serializer):
    name = serializers.CharField(max_length=40, required=False, default="我的家庭")
    nickname = serializers.CharField(max_length=30)


class UpdateFamilySerializer(serializers.Serializer):
    name = serializers.CharField(max_length=40)


class JoinFamilySerializer(serializers.Serializer):
    code = serializers.RegexField(r"^\d{6}$")
    nickname = serializers.CharField(max_length=30)


class UpdateNicknameSerializer(serializers.Serializer):
    nickname = serializers.CharField(max_length=30)


class TransferAdminSerializer(serializers.Serializer):
    member_id = serializers.UUIDField()
