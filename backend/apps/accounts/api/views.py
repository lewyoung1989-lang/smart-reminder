from django.contrib.auth import authenticate, get_user_model
from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import PhoneIdentity
from apps.accounts.services.revocation import revoke_all_refresh_tokens
from apps.accounts.services.tokens import authentication_payload, user_summary

from .serializers import (
    LoginSerializer,
    PasswordChangeSerializer,
    RefreshSerializer,
    RegisterSerializer,
)


class RegisterView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        try:
            with transaction.atomic():
                user = get_user_model().objects.create_user(
                    username=data["phone_e164"],
                    password=data["password"],
                )
                PhoneIdentity.objects.create(
                    user=user,
                    phone_e164=data["phone_e164"],
                )
        except IntegrityError:
            return Response(
                {"code": "phone_already_registered"},
                status=status.HTTP_409_CONFLICT,
            )
        return Response(
            authentication_payload(user),
            status=status.HTTP_201_CREATED,
        )


class LoginView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = authenticate(
            request=request,
            username=data["phone"],
            password=data["password"],
        )
        if user is None or not hasattr(user, "phone_identity"):
            return Response(
                {"code": "invalid_credentials"},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        return Response(authentication_payload(user), status=status.HTTP_200_OK)


class RefreshView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        refresh_serializer = TokenRefreshSerializer(
            data={"refresh": serializer.validated_data["refresh_token"]}
        )
        try:
            refresh_serializer.is_valid(raise_exception=True)
        except TokenError:
            return Response(
                {"code": "invalid_refresh_token"},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        result = refresh_serializer.validated_data
        return Response(
            {
                "access_token": result["access"],
                "refresh_token": result["refresh"],
                "access_expires_in": 900,
            },
            status=status.HTTP_200_OK,
        )


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        if not hasattr(request.user, "phone_identity"):
            return Response(
                {"code": "account_identity_missing"},
                status=status.HTTP_409_CONFLICT,
            )
        return Response(user_summary(request.user), status=status.HTTP_200_OK)


def _blacklist_users_refresh(raw_token, user):
    try:
        token = RefreshToken(raw_token)
    except TokenError:
        try:
            unverified = RefreshToken(raw_token, verify=False)
            outstanding = OutstandingToken.objects.get(
                jti=unverified["jti"],
                user=user,
            )
        except (TokenError, KeyError, OutstandingToken.DoesNotExist):
            return False
        return BlacklistedToken.objects.filter(token=outstanding).exists()

    if str(token.get("user_id")) != str(user.pk):
        return False
    token.blacklist()
    return True


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        if not _blacklist_users_refresh(
            serializer.validated_data["refresh_token"],
            request.user,
        ):
            return Response(
                {"code": "invalid_refresh_token"},
                status=status.HTTP_400_BAD_REQUEST,
            )
        return Response(status=status.HTTP_204_NO_CONTENT)


class PasswordChangeView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        serializer = PasswordChangeSerializer(
            data=request.data,
            context={"user": request.user},
        )
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        if not request.user.check_password(data["current_password"]):
            return Response(
                {
                    "code": "invalid_current_password",
                    "field": "current_password",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )
        with transaction.atomic():
            request.user.set_password(data["new_password"])
            request.user.save(update_fields=["password"])
            revoke_all_refresh_tokens(request.user)
            payload = authentication_payload(request.user)
        return Response(payload, status=status.HTTP_200_OK)
