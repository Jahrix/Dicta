from __future__ import annotations

import shutil
import subprocess
import tempfile
import wave
from dataclasses import dataclass
from pathlib import Path

from fastapi import UploadFile
from pydub import AudioSegment

from ..settings import Settings


class AudioValidationError(Exception):
    pass


@dataclass
class PreparedAudio:
    temp_dir: Path
    source_path: Path
    wav_path: Path
    size_bytes: int
    duration_seconds: int

    def cleanup(self) -> None:
        shutil.rmtree(self.temp_dir, ignore_errors=True)


_ALLOWED_SUFFIXES = {".wav", ".m4a", ".caf", ".mp3", ".mp4", ".aac", ".ogg", ".webm"}


def _resolve_binary(binary: str) -> str | None:
    candidate = Path(binary)
    if candidate.is_file():
        return str(candidate)
    return shutil.which(binary)


def _suffix_for_upload(upload: UploadFile) -> str:
    suffix = Path(upload.filename or "upload").suffix.lower()
    if suffix not in _ALLOWED_SUFFIXES:
        raise AudioValidationError(f"Unsupported audio type: {suffix or 'unknown'}")
    return suffix


async def save_upload(upload: UploadFile, settings: Settings) -> tuple[Path, Path, int]:
    temp_dir = Path(tempfile.mkdtemp(prefix="dicta-cloud-"))
    suffix = _suffix_for_upload(upload)
    source_path = temp_dir / f"input{suffix}"
    wav_path = temp_dir / "normalized.wav"

    bytes_written = 0
    with source_path.open("wb") as handle:
        while True:
            chunk = await upload.read(1024 * 1024)
            if not chunk:
                break
            bytes_written += len(chunk)
            if bytes_written > settings.max_file_bytes:
                raise AudioValidationError(f"File too large; max {settings.max_file_bytes} bytes")
            handle.write(chunk)

    if bytes_written == 0:
        raise AudioValidationError("Uploaded file is empty")

    return temp_dir, source_path, bytes_written


def _probe_wav_duration_seconds(path: Path) -> int:
    with wave.open(str(path), "rb") as wav_file:
        frame_count = wav_file.getnframes()
        frame_rate = wav_file.getframerate()
        if frame_rate <= 0:
            raise AudioValidationError("Invalid WAV file")
        seconds = frame_count / float(frame_rate)
    return max(1, int(round(seconds)))


def _probe_duration_seconds(path: Path, settings: Settings) -> int:
    ffprobe = _resolve_binary(settings.ffprobe_binary)
    if ffprobe:
        result = subprocess.run(
            [
                ffprobe,
                "-v",
                "error",
                "-show_entries",
                "format=duration",
                "-of",
                "default=noprint_wrappers=1:nokey=1",
                str(path),
            ],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return max(1, int(round(float(result.stdout.strip()))))

    if path.suffix.lower() == ".wav":
        return _probe_wav_duration_seconds(path)

    try:
        audio = AudioSegment.from_file(path)
    except Exception as exc:  # pragma: no cover - best effort fallback
        raise AudioValidationError("Could not determine audio duration; install ffprobe or provide WAV input") from exc
    return max(1, int(round(len(audio) / 1000)))


def _convert_with_ffmpeg(source_path: Path, wav_path: Path, settings: Settings) -> bool:
    ffmpeg = _resolve_binary(settings.ffmpeg_binary)
    if not ffmpeg:
        return False

    result = subprocess.run(
        [
            ffmpeg,
            "-nostdin",
            "-y",
            "-i",
            str(source_path),
            "-ac",
            "1",
            "-ar",
            "16000",
            "-c:a",
            "pcm_s16le",
            str(wav_path),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise AudioValidationError(f"ffmpeg conversion failed: {result.stderr.strip() or result.stdout.strip()}")
    return True


def _convert_with_pydub(source_path: Path, wav_path: Path) -> None:
    try:
        audio = AudioSegment.from_file(source_path)
    except Exception as exc:  # pragma: no cover - best effort fallback
        raise AudioValidationError("Audio conversion failed and ffmpeg is unavailable") from exc
    audio.set_frame_rate(16000).set_channels(1).export(wav_path, format="wav")


async def prepare_audio(upload: UploadFile, settings: Settings) -> PreparedAudio:
    temp_dir, source_path, size_bytes = await save_upload(upload, settings)
    wav_path = temp_dir / "normalized.wav"

    try:
        converted = _convert_with_ffmpeg(source_path, wav_path, settings)
        if not converted:
            if source_path.suffix.lower() == ".wav":
                _convert_with_pydub(source_path, wav_path)
            else:
                raise AudioValidationError("ffmpeg is required for non-WAV uploads")

        duration_seconds = _probe_duration_seconds(wav_path, settings)
        if duration_seconds > settings.max_audio_seconds:
            raise AudioValidationError(f"Audio too long; max {settings.max_audio_seconds} seconds")

        return PreparedAudio(
            temp_dir=temp_dir,
            source_path=source_path,
            wav_path=wav_path,
            size_bytes=size_bytes,
            duration_seconds=duration_seconds,
        )
    except Exception:
        shutil.rmtree(temp_dir, ignore_errors=True)
        raise
