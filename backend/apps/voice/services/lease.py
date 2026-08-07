from dataclasses import dataclass, field
from uuid import uuid4

from redis import Redis


COMPARE_AND_DELETE = """
if redis.call('get', KEYS[1]) == ARGV[1] then
    return redis.call('del', KEYS[1])
end
return 0
""".strip()


@dataclass
class RedisLease:
    redis_client: object
    key: str
    owner_token: str
    _released: bool = field(default=False, init=False)

    def release(self):
        if self._released:
            return
        self._released = True
        self.redis_client.eval(
            COMPARE_AND_DELETE,
            1,
            self.key,
            self.owner_token,
        )

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, traceback):
        self.release()


class RedisLeaseManager:
    def __init__(self, redis_client, *, ttl_seconds):
        self.redis_client = redis_client
        self.ttl_seconds = ttl_seconds

    @classmethod
    def from_url(cls, url, *, ttl_seconds):
        return cls(Redis.from_url(url), ttl_seconds=ttl_seconds)

    def acquire(self, key):
        owner_token = uuid4().hex
        acquired = self.redis_client.set(
            key,
            owner_token,
            nx=True,
            ex=self.ttl_seconds,
        )
        if not acquired:
            return None
        return RedisLease(
            redis_client=self.redis_client,
            key=key,
            owner_token=owner_token,
        )
