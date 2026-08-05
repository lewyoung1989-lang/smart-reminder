from dataclasses import dataclass


@dataclass(frozen=True)
class AsrResult:
    transcript: str
    latency_ms: int
    provider: str


class AsrError(Exception):
    pass


class AsrResponseError(AsrError):
    pass


class AsrTimeoutError(AsrError):
    pass


class AsrUnavailableError(AsrError):
    pass


class EmptyTranscriptError(AsrError):
    pass
