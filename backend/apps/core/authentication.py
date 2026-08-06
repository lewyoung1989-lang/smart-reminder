from rest_framework.authentication import BaseAuthentication, TokenAuthentication
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication


class LegacyBearerTokenAuthentication(TokenAuthentication):
    keyword = "Bearer"


class CompositeBearerAuthentication(BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        header = request.META.get("HTTP_AUTHORIZATION", "")
        parts = header.split()
        if not parts or parts[0].lower() != self.keyword.lower():
            return None
        if len(parts) != 2:
            raise AuthenticationFailed("Invalid authorization header.")

        raw_token = parts[1]
        if raw_token.count(".") == 2:
            return JWTAuthentication().authenticate(request)
        return LegacyBearerTokenAuthentication().authenticate(request)

    def authenticate_header(self, request):
        return self.keyword


BearerTokenAuthentication = CompositeBearerAuthentication
