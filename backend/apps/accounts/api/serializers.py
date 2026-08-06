from django.contrib.auth import get_user_model
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from rest_framework import serializers
from rest_framework.exceptions import APIException

from apps.accounts.phone import InvalidPhone, normalize_mainland_phone


class AuthInputError(APIException):
    status_code = 400

    def __init__(self, code, field):
        super().__init__({"code": code, "field": field})


class RegisterSerializer(serializers.Serializer):
    phone = serializers.CharField(trim_whitespace=True)
    password = serializers.CharField(trim_whitespace=False, write_only=True)
    password_confirm = serializers.CharField(
        trim_whitespace=False,
        write_only=True,
    )

    def validate(self, attrs):
        try:
            attrs["phone_e164"] = normalize_mainland_phone(attrs["phone"])
        except InvalidPhone as exc:
            raise AuthInputError("invalid_phone", "phone") from exc

        if attrs["password"] != attrs["password_confirm"]:
            raise AuthInputError("password_mismatch", "password_confirm")
        if len(attrs["password"]) > 64:
            raise AuthInputError("weak_password", "password")

        candidate = get_user_model()(username=attrs["phone_e164"])
        try:
            validate_password(attrs["password"], user=candidate)
        except DjangoValidationError as exc:
            raise AuthInputError("weak_password", "password") from exc
        return attrs


class LoginSerializer(serializers.Serializer):
    phone = serializers.CharField(trim_whitespace=True)
    password = serializers.CharField(trim_whitespace=False, write_only=True)

    def validate_phone(self, value):
        try:
            return normalize_mainland_phone(value)
        except InvalidPhone as exc:
            raise AuthInputError("invalid_phone", "phone") from exc


class RefreshSerializer(serializers.Serializer):
    refresh_token = serializers.CharField(trim_whitespace=False)
