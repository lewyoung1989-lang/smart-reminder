from contextlib import asynccontextmanager

from fastapi import FastAPI, File, Form, HTTPException, UploadFile

from .audio import AudioInputError, normalize_wav
from .engine import FunAsrEngine


DEFAULT_MAX_AUDIO_BYTES = 4 * 1024 * 1024


def create_app(
    *,
    engine=None,
    normalizer=None,
    load_on_startup=True,
    max_audio_bytes=DEFAULT_MAX_AUDIO_BYTES,
):
    engine = engine or FunAsrEngine()
    normalizer = normalizer or normalize_wav

    @asynccontextmanager
    async def lifespan(_app):
        if load_on_startup:
            engine.load()
        yield

    app = FastAPI(title="smart-reminder-funasr", lifespan=lifespan)

    @app.get("/health")
    def health():
        if not engine.ready:
            raise HTTPException(
                status_code=503,
                detail={"code": "asr_unavailable"},
            )
        return {"status": "ok", "ready": True}

    @app.post("/v1/audio/transcriptions")
    async def transcribe(
        file: UploadFile = File(...),
        model: str = Form(...),
        response_format: str = Form("json"),
    ):
        if not engine.ready:
            raise HTTPException(503, detail={"code": "asr_unavailable"})
        if model != "paraformer-zh" or response_format != "json":
            raise HTTPException(400, detail={"code": "invalid_request"})

        try:
            payload = await file.read(max_audio_bytes + 1)
        finally:
            await file.close()
        if len(payload) > max_audio_bytes:
            raise HTTPException(413, detail={"code": "audio_too_large"})

        try:
            normalized = normalizer(payload)
        except AudioInputError as exc:
            raise HTTPException(400, detail={"code": exc.code}) from exc

        transcript = engine.transcribe(normalized.tensor).strip()
        if not transcript:
            raise HTTPException(422, detail={"code": "empty_transcript"})
        return {"text": transcript}

    return app


app = create_app()
