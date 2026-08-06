import logging

from django.contrib.auth import authenticate, get_user_model
from django.db import IntegrityError, transaction
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from rest_framework_simplejwt.settings import api_settings
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)
from rest_framework_simplejwt.tokens import RefreshToken

from apps.accounts.models import PhoneIdentity
from apps.accounts.services.revocation import revoke_all_refresh_tokens
from apps.accounts.services.tokens import authentication_payload, user_summary
from apps.accounts.throttling import (
    FixedWindowRateLimiter,
    client_ip,
    private_value_key,
)

from .serializers import (
    LoginSerializer,
    PasswordChangeSerializer,
    RefreshSerializer,
    RegisterSerializer,
)


logger = logging.getLogger(__name__)


def _rate_limited(retry_after):
    return Response(
        {"code": "rate_limited", "retry_after": retry_after},
        status=status.HTTP_429_TOO_MANY_REQUESTS,
        headers={"Retry-After": str(retry_after)},
    )


def _limited_retry_after(*limits):
    return max(retry_after for limited, retry_after in limits if limited)


def _lock_refresh_user(raw_token):
    try:
        token = RefreshToken(raw_token, verify=False)
        user_id = token[api_settings.USER_ID_CLAIM]
    except (KeyError, TokenError):
        return None
    lookup = {api_settings.USER_ID_FIELD: user_id}
    try:
        return get_user_model().objects.select_for_update().get(**lookup)
    except get_user_model().DoesNotExist:
        return None


class RegisterView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RegisterSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        limiter = FixedWindowRateLimiter()
        limited_ip, retry_ip, _ = limiter.consume(
            "register_ip",
            client_ip(request),
        )
        limited_phone, retry_phone, _ = limiter.consume(
            "register_phone",
            data["phone_e164"],
        )
        if limited_ip or limited_phone:
            return _rate_limited(
                _limited_retry_after(
                    (limited_ip, retry_ip),
                    (limited_phone, retry_phone),
                )
            )
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
        limiter = FixedWindowRateLimiter()
        ip = client_ip(request)
        combo = f"{ip}:{data['phone']}"
        combo_limited, combo_retry, _ = limiter.is_limited(
            "login_combo",
            combo,
        )
        ip_limited, ip_retry, _ = limiter.is_limited("login_ip", ip)
        if combo_limited or ip_limited:
            return _rate_limited(
                _limited_retry_after(
                    (combo_limited, combo_retry),
                    (ip_limited, ip_retry),
                )
            )
        user = authenticate(
            request=request,
            username=data["phone"],
            password=data["password"],
        )
        if user is None or not hasattr(user, "phone_identity"):
            limiter.consume("login_combo", combo)
            limiter.consume("login_ip", ip)
            logger.info(
                "auth_login_failed phone_key=%s",
                private_value_key(data["phone"])[:12],
            )
            return Response(
                {"code": "invalid_credentials"},
                status=status.HTTP_401_UNAUTHORIZED,
            )
        limiter.clear("login_combo", combo)
        logger.info("auth_login_succeeded user_id=%s", user.pk)
        return Response(authentication_payload(user), status=status.HTTP_200_OK)


class RefreshView(APIView):
    authentication_classes = []
    permission_classes = [AllowAny]

    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        limited, retry_after, _ = FixedWindowRateLimiter().consume(
            "refresh_ip",
            client_ip(request),
        )
        if limited:
            return _rate_limited(retry_after)
        raw_token = serializer.validated_data["refresh_token"]
        try:
            with transaction.atomic():
                if _lock_refresh_user(raw_token) is None:
                    raise TokenError("Token user does not exist")
                refresh_serializer = TokenRefreshSerializer(
                    data={"refresh": raw_token}
                )
                refresh_serializer.is_valid(raise_exception=True)
                result = dict(refresh_serializer.validated_data)
        except TokenError:
            return Response(
                {"code": "invalid_refresh_token"},
                status=status.HTTP_401_UNAUTHORIZED,
            )
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
        with transaction.atomic():
            user = (
                get_user_model()
                .objects.select_for_update()
                .get(pk=request.user.pk)
            )
            if not user.check_password(data["current_password"]):
                return Response(
                    {
                        "code": "current_password_invalid",
                        "field": "current_password",
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            user.set_password(data["new_password"])
            user.save(update_fields=["password"])
            revoke_all_refresh_tokens(user)
            payload = authentication_payload(user)
        return Response(payload, status=status.HTTP_200_OK)
