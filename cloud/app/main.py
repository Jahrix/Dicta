from __future__ import annotations

import json
import logging
import time
import uuid
from typing import Annotated

from fastapi import Depends, FastAPI, File, Form, HTTPException, Request, UploadFile
from fastapi.responses import JSONResponse
from slowapi.errors import RateLimitExceeded

from .auth import AuthenticatedKey, require_api_key
from .asr.audio import AudioValidationError, PreparedAudio, prepare_audio
from .asr.whisper_backend import ASRError, transcribe_wav
from .limits import api_key_rate_limit_key, limiter, rate_limit_exceeded_handler
from .postprocess import apply_prompt_term_replacements, normalize_whitespace
from .quota import ReservedQuota, release_quota, reserve_quota_or_raise
from .settings import Settings, get_settings
from .storage import init_db


settings = get_settings()
logging.basicConfig(level=getattr(logging, settings.log_level.upper(), logging.INFO), format="%(message)s")
logger = logging.getLogger("dicta.cloud")

app = FastAPI(title=settings.app_name, version=settings.app_version)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_exceeded_handler)


class JsonLogFormatter:
    @staticmethod
    def emit(event: str, **fields: object) -> None:
        logger.info(json.dumps({"event": event, **fields}, default=str, sort_keys=True))


def _clean_prompt_terms(prompt_terms: list[str] | None, settings: Settings) -> list[str]:
    cleaned: list[str] = []
    for term in prompt_terms or []:
        normalized = normalize_whitespace(term)
        if not normalized:
            continue
        cleaned.append(normalized[: settings.max_prompt_term_length])
        if len(cleaned) >= settings.max_prompt_terms:
            break
    return cleaned


@app.on_event("startup")
def startup() -> None:
    init_db(settings.sqlite_path)
    JsonLogFormatter.emit(
        "startup",
        version=settings.app_version,
        backend=settings.asr_backend,
        sqlite_path=str(settings.sqlite_path),
    )


@app.middleware("http")
async def add_request_context(request: Request, call_next):
    request_id = uuid.uuid4().hex
    request.state.request_id = request_id
    started = time.perf_counter()

    try:
        response = await call_next(request)
    except Exception as exc:
        JsonLogFormatter.emit(
            "request_error",
            request_id=request_id,
            method=request.method,
            path=request.url.path,
            client=getattr(request.client, "host", None),
            error_type=type(exc).__name__,
            error=str(exc),
            duration_ms=int((time.perf_counter() - started) * 1000),
        )
        raise

    response.headers["X-Request-ID"] = request_id
    JsonLogFormatter.emit(
        "request_complete",
        request_id=request_id,
        method=request.method,
        path=request.url.path,
        client=getattr(request.client, "host", None),
        status_code=response.status_code,
        key_label=getattr(request.state, "api_key_label", None),
        duration_ms=int((time.perf_counter() - started) * 1000),
    )
    return response


@app.exception_handler(AudioValidationError)
async def audio_validation_exception_handler(request: Request, exc: AudioValidationError) -> JSONResponse:
    return JSONResponse(
        status_code=400,
        content={
            "error": "invalid_audio",
            "message": str(exc),
            "request_id": getattr(request.state, "request_id", None),
        },
    )


@app.exception_handler(ASRError)
async def asr_exception_handler(request: Request, exc: ASRError) -> JSONResponse:
    JsonLogFormatter.emit(
        "asr_error",
        request_id=getattr(request.state, "request_id", None),
        key_label=getattr(request.state, "api_key_label", None),
        message=str(exc),
    )
    return JSONResponse(
        status_code=502,
        content={
            "error": "asr_backend_failed",
            "message": str(exc),
            "request_id": getattr(request.state, "request_id", None),
        },
    )


@app.get("/healthz")
async def healthz() -> dict[str, object]:
    return {
        "status": "ok",
        "version": settings.app_version,
        "backend": settings.asr_backend,
        "model": settings.model_size,
    }


@app.post("/v1/transcribe")
@limiter.limit(settings.rate_limit_per_ip)
@limiter.limit(settings.rate_limit_per_key, key_func=api_key_rate_limit_key)
async def transcribe(
    request: Request,
    file: Annotated[UploadFile, File(...)],
    language: Annotated[str, Form()] = settings.default_language,
    mode: Annotated[str, Form()] = "docs",
    prompt_terms: Annotated[list[str] | None, Form()] = None,
    auth_key: AuthenticatedKey = Depends(require_api_key),
) -> dict[str, object]:
    if mode not in {"docs", "chat", "code"}:
        raise HTTPException(
            status_code=422,
            detail={
                "error": "invalid_mode",
                "message": "mode must be one of: docs, chat, code",
                "request_id": getattr(request.state, "request_id", None),
            },
        )

    prepared: PreparedAudio | None = None
    reservation: ReservedQuota | None = None
    cleaned_terms = _clean_prompt_terms(prompt_terms, settings)
    started = time.perf_counter()

    try:
        prepared = await prepare_audio(file, settings)
        reservation = reserve_quota_or_raise(request, auth_key, prepared.duration_seconds)

        JsonLogFormatter.emit(
            "transcribe_start",
            request_id=request.state.request_id,
            key_label=auth_key.label,
            filename=file.filename,
            size_bytes=prepared.size_bytes,
            audio_seconds=prepared.duration_seconds,
            language=language,
            mode=mode,
            backend=settings.asr_backend,
        )

        result = transcribe_wav(prepared.wav_path, language=language, mode=mode, prompt_terms=cleaned_terms, settings=settings)
        processed_text = apply_prompt_term_replacements(result.text, cleaned_terms)
        if not processed_text:
            raise HTTPException(
                status_code=422,
                detail={
                    "error": "empty_transcript",
                    "message": "No speech detected",
                    "request_id": getattr(request.state, "request_id", None),
                },
            )

        duration_ms = int((time.perf_counter() - started) * 1000)
        JsonLogFormatter.emit(
            "transcribe_success",
            request_id=request.state.request_id,
            key_label=auth_key.label,
            audio_seconds=prepared.duration_seconds,
            engine=result.engine,
            output_chars=len(processed_text),
            duration_ms=duration_ms,
            quota_remaining_seconds=reservation.snapshot.remaining_seconds if reservation else None,
        )
        return {
            "text": processed_text,
            "engine": result.engine,
            "language": result.language,
            "duration_ms": duration_ms,
        }
    except HTTPException:
        raise
    except Exception:
        release_quota(auth_key, reservation)
        raise
    finally:
        if prepared is not None:
            prepared.cleanup()
