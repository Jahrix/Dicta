from __future__ import annotations

import subprocess
import tempfile
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from ..settings import Settings


class ASRError(Exception):
    pass


@dataclass(frozen=True)
class TranscriptionResult:
    text: str
    engine: str
    language: str
    duration_ms: int


_MODEL_CACHE: dict[tuple[str, str, int], object] = {}
_MODEL_LOCK = threading.Lock()


def _build_initial_prompt(mode: str, prompt_terms: list[str]) -> str | None:
    mode_hints = {
        "docs": "Transcribe dictation with clear punctuation and sentence casing.",
        "chat": "Transcribe casual chat naturally.",
        "code": "Transcribe code and technical identifiers literally when possible.",
    }
    fragments = [mode_hints.get(mode, "")]
    if prompt_terms:
        fragments.append("Important terms: " + ", ".join(prompt_terms))
    prompt = " ".join(fragment for fragment in fragments if fragment).strip()
    return prompt or None


def _get_faster_whisper_model(settings: Settings):
    cache_key = (settings.model_size, settings.device, settings.threads)
    with _MODEL_LOCK:
        model = _MODEL_CACHE.get(cache_key)
        if model is not None:
            return model

        try:
            from faster_whisper import WhisperModel
        except ImportError as exc:  # pragma: no cover - dependency issue
            raise ASRError("faster-whisper is not installed") from exc

        compute_type = "int8" if settings.device == "cpu" else "float16"
        model = WhisperModel(
            settings.model_size,
            device=settings.device,
            cpu_threads=settings.threads,
            compute_type=compute_type,
        )
        _MODEL_CACHE[cache_key] = model
        return model


def _transcribe_with_faster_whisper(wav_path: Path, language: str, mode: str, prompt_terms: list[str], settings: Settings) -> TranscriptionResult:
    model = _get_faster_whisper_model(settings)
    initial_prompt = _build_initial_prompt(mode, prompt_terms)
    started = time.perf_counter()
    segments, info = model.transcribe(
        str(wav_path),
        language=language,
        initial_prompt=initial_prompt,
        beam_size=5,
        vad_filter=True,
        condition_on_previous_text=False,
        word_timestamps=False,
    )
    text = " ".join(segment.text.strip() for segment in segments if segment.text.strip()).strip()
    duration_ms = int((time.perf_counter() - started) * 1000)
    detected_language = getattr(info, "language", language) or language
    return TranscriptionResult(text=text, engine="faster-whisper", language=detected_language, duration_ms=duration_ms)


def _transcribe_with_whisper_cpp(wav_path: Path, language: str, mode: str, prompt_terms: list[str], settings: Settings) -> TranscriptionResult:
    if not settings.whisper_cpp_binary or not settings.whisper_cpp_model_path:
        raise ASRError("WHISPER_CPP_BINARY and WHISPER_CPP_MODEL_PATH are required for whisper_cpp backend")

    output_dir = Path(tempfile.mkdtemp(prefix="dicta-whispercpp-"))
    output_base = output_dir / "transcript"
    prompt = _build_initial_prompt(mode, prompt_terms)
    command = [
        settings.whisper_cpp_binary,
        "-m",
        settings.whisper_cpp_model_path,
        "-f",
        str(wav_path),
        "-l",
        language,
        "-nt",
        "-np",
        "-of",
        str(output_base),
        "-otxt",
    ]
    if prompt:
        command.extend(["-p", prompt])

    started = time.perf_counter()
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    duration_ms = int((time.perf_counter() - started) * 1000)
    if result.returncode != 0:
        stderr_tail = (result.stderr or result.stdout or "").strip().splitlines()[-10:]
        raise ASRError("whisper.cpp failed: " + " | ".join(stderr_tail))

    txt_path = output_base.with_suffix(".txt")
    if txt_path.exists():
        text = txt_path.read_text(encoding="utf-8").strip()
    else:
        text = result.stdout.strip()

    return TranscriptionResult(text=text, engine="whisper-cpp", language=language, duration_ms=duration_ms)


def transcribe_wav(wav_path: Path, language: str, mode: str, prompt_terms: list[str], settings: Settings) -> TranscriptionResult:
    backend = settings.asr_backend.lower()
    if backend == "faster_whisper":
        return _transcribe_with_faster_whisper(wav_path, language, mode, prompt_terms, settings)
    if backend == "whisper_cpp":
        return _transcribe_with_whisper_cpp(wav_path, language, mode, prompt_terms, settings)
    raise ASRError(f"Unsupported ASR_BACKEND: {settings.asr_backend}")
