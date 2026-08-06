import hashlib
import hmac
import time

from django.conf import settings
from django.core.cache import caches


def private_value_key(value):
    return hmac.new(
        settings.SECRET_KEY.encode(),
        value.encode(),
        hashlib.sha256,
    ).hexdigest()


def client_ip(request):
    forwarded = request.META.get("HTTP_X_FORWARDED_FOR", "")
    if forwarded:
        return forwarded.split(",")[-1].strip()
    return request.META.get("REMOTE_ADDR", "unknown")


class FixedWindowRateLimiter:
    def __init__(self, cache_alias="auth"):
        self.cache = caches[cache_alias]

    def _parts(self, scope, dimension):
        limit, window = settings.AUTH_RATE_LIMITS[scope]
        now = int(time.time())
        bucket = now // window
        digest = private_value_key(dimension)
        key = f"auth:{scope}:{digest}:{bucket}"
        retry_after = window - (now % window)
        return key, limit, window, retry_after

    def consume(self, scope, dimension):
        key, limit, window, retry_after = self._parts(scope, dimension)
        if self.cache.add(key, 1, timeout=window + 1):
            count = 1
        else:
            count = self.cache.incr(key)
        return count > limit, retry_after, key

    def is_limited(self, scope, dimension):
        key, limit, _, retry_after = self._parts(scope, dimension)
        return int(self.cache.get(key, 0)) >= limit, retry_after, key

    def clear(self, scope, dimension):
        key, _, _, _ = self._parts(scope, dimension)
        self.cache.delete(key)
