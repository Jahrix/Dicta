from __future__ import annotations

import os
from dataclasses import dataclass
from functools import lru_cache
from pathlib import Path


CLOUD_ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DB_PATH = CLOUD_ROOT / "data" / "dicta_cloud.sqlite3"


def _env_int(name: str, default: int) -> int:
    value = os.getenv(name)
    if value is None or value == "":
        return default
    return int(value)


def _env_str(name: str, default: str) -> str:
    value = os.getenv(name)
    return value if value not in (None, "") else default


@dataclass(frozen=True)
class Settings:
    app_name: str
    app_version: str
    host: str
    port: int
    log_level: str
    sqlite_path: Path
    asr_backend: str
    model_size: str
    device: str
    threads: int
    ffmpeg_binary: str
    ffprobe_binary: str
    whisper_cpp_binary: str | None
    whisper_cpp_model_path: str | None
    default_language: str
    max_file_bytes: int
    max_audio_seconds: int
    rate_limit_per_ip: str
    rate_limit_per_key: str
    max_prompt_terms: int
    max_prompt_term_length: int


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    threads_value = _env_str("THREADS", "auto")
    threads = os.cpu_count() or 4 if threads_value == "auto" else int(threads_value)

    return Settings(
        app_name=_env_str("APP_NAME", "Dicta Cloud"),
        app_version=_env_str("APP_VERSION", "0.1.0"),
        host=_env_str("HOST", "0.0.0.0"),
        port=_env_int("PORT", 8000),
        log_level=_env_str("LOG_LEVEL", "INFO"),
        sqlite_path=Path(_env_str("SQLITE_PATH", str(DEFAULT_DB_PATH))).expanduser(),
        asr_backend=_env_str("ASR_BACKEND", "faster_whisper"),
        model_size=_env_str("MODEL_SIZE", "small.en"),
        device=_env_str("DEVICE", "cpu"),
        threads=threads,
        ffmpeg_binary=_env_str("FFMPEG_BINARY", "ffmpeg"),
        ffprobe_binary=_env_str("FFPROBE_BINARY", "ffprobe"),
        whisper_cpp_binary=os.getenv("WHISPER_CPP_BINARY"),
        whisper_cpp_model_path=os.getenv("WHISPER_CPP_MODEL_PATH"),
        default_language=_env_str("DEFAULT_LANGUAGE", "en"),
        max_file_bytes=_env_int("MAX_FILE_BYTES", 15 * 1024 * 1024),
        max_audio_seconds=_env_int("MAX_AUDIO_SECONDS", 120),
        rate_limit_per_ip=_env_str("RATE_LIMIT_PER_IP", "30/minute"),
        rate_limit_per_key=_env_str("RATE_LIMIT_PER_KEY", "10/minute"),
        max_prompt_terms=_env_int("MAX_PROMPT_TERMS", 16),
        max_prompt_term_length=_env_int("MAX_PROMPT_TERM_LENGTH", 64),
    )
