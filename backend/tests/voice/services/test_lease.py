from apps.voice.services.lease import InMemoryLeaseManager, RedisLeaseManager


class FakeRedis:
    def __init__(self):
        self.values = {}
        self.set_calls = []
        self.eval_calls = []

    def set(self, key, value, *, nx, ex):
        self.set_calls.append((key, value, nx, ex))
        if nx and key in self.values:
            return False
        self.values[key] = value
        return True

    def eval(self, script, numkeys, key, token):
        self.eval_calls.append((script, numkeys, key, token))
        if self.values.get(key) != token:
            return 0
        del self.values[key]
        return 1


def test_acquires_non_blocking_lease_with_unique_owner_and_ttl():
    redis = FakeRedis()
    manager = RedisLeaseManager(redis, ttl_seconds=25)

    lease = manager.acquire("voice:asr:global")

    assert lease is not None
    assert redis.set_calls == [
        ("voice:asr:global", lease.owner_token, True, 25),
    ]


def test_returns_none_when_lease_is_contended():
    redis = FakeRedis()
    redis.values["voice:asr:global"] = "existing-owner"
    manager = RedisLeaseManager(redis, ttl_seconds=25)

    assert manager.acquire("voice:asr:global") is None


def test_context_manager_releases_only_with_owner_token():
    redis = FakeRedis()
    manager = RedisLeaseManager(redis, ttl_seconds=25)

    with manager.acquire("voice:asr:global") as lease:
        assert redis.values[lease.key] == lease.owner_token

    script, numkeys, key, token = redis.eval_calls[0]
    assert "redis.call('get', KEYS[1]) == ARGV[1]" in script
    assert "redis.call('del', KEYS[1])" in script
    assert (numkeys, key, token) == (
        1,
        "voice:asr:global",
        lease.owner_token,
    )
    assert key not in redis.values


def test_stale_owner_cannot_release_replacement_lease():
    redis = FakeRedis()
    manager = RedisLeaseManager(redis, ttl_seconds=25)
    stale_lease = manager.acquire("voice:asr:global")
    redis.values[stale_lease.key] = "replacement-owner"

    stale_lease.release()

    assert redis.values[stale_lease.key] == "replacement-owner"


def test_release_is_idempotent():
    redis = FakeRedis()
    lease = RedisLeaseManager(redis, ttl_seconds=25).acquire("voice:asr:global")

    lease.release()
    lease.release()

    assert len(redis.eval_calls) == 1


def test_in_memory_lease_is_non_blocking_and_reusable_after_release():
    manager = InMemoryLeaseManager()
    lease = manager.acquire("voice:asr:global")

    assert lease is not None
    assert manager.acquire("voice:asr:global") is None

    lease.release()

    assert manager.acquire("voice:asr:global") is not None


def test_in_memory_release_is_idempotent():
    manager = InMemoryLeaseManager()
    lease = manager.acquire("voice:asr:global")

    lease.release()
    lease.release()

    replacement = manager.acquire("voice:asr:global")
    assert replacement is not None
