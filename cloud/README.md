# Dicta Cloud v0

Minimal FastAPI transcription API for Dicta. It provides:
- Bearer API key auth with hashed key storage in sqlite
- Rate limiting via SlowAPI
- Daily quota enforcement per key
- Audio normalization to 16kHz mono WAV
- Configurable ASR backend: `faster_whisper` or `whisper_cpp`
- Structured JSON logs and `/healthz`

## Endpoints

### `POST /v1/transcribe`
Multipart form fields:
- `file`: required audio file (`wav`, `m4a`, `caf`, `mp3`, `mp4`, `aac`, `ogg`, `webm`)
- `language`: optional, defaults to `en`
- `mode`: optional, one of `docs`, `chat`, `code`
- `prompt_terms`: optional repeated form field, capped server-side

Response:

```json
{
  "text": "hello world",
  "engine": "faster-whisper",
  "language": "en",
  "duration_ms": 1234
}
```

### `GET /healthz`
Returns version, backend, and model info.

## Local development

Requirements:
- Python 3.11+
- `ffmpeg` and `ffprobe` on `PATH` for non-WAV uploads

Install:

```bash
cd cloud
python3 -m venv .venv
source .venv/bin/activate
pip install -e .
python -m app.storage init-db
python -m app.storage create-key --label "indus" --quota-minutes 60
uvicorn app.main:app --reload
```

Useful env vars:

```bash
export SQLITE_PATH="$PWD/data/dicta_cloud.sqlite3"
export ASR_BACKEND=faster_whisper
export MODEL_SIZE=small.en
export DEVICE=cpu
export THREADS=auto
export RATE_LIMIT_PER_IP=30/minute
export RATE_LIMIT_PER_KEY=10/minute
export MAX_AUDIO_SECONDS=120
export MAX_FILE_BYTES=$((15 * 1024 * 1024))
```

For `whisper_cpp` instead:

```bash
export ASR_BACKEND=whisper_cpp
export WHISPER_CPP_BINARY=/usr/local/bin/whisper-cli
export WHISPER_CPP_MODEL_PATH=/models/ggml-small.en.bin
```

## API key admin

Create a key:

```bash
cd cloud
python -m app.storage create-key --label "indus" --quota-minutes 60
```

List stored keys:

```bash
python -m app.storage list-keys
```

Keys are stored hashed with SHA-256 in sqlite. The raw key is shown only once when created.

## Curl examples

Unauthorized request:

```bash
curl -i http://127.0.0.1:8000/v1/transcribe
```

Authorized transcription request:

```bash
export DICTA_API_KEY="dicta_replace_me"
curl -sS http://127.0.0.1:8000/v1/transcribe \
  -H "Authorization: Bearer ${DICTA_API_KEY}" \
  -F "file=@/absolute/path/to/sample.m4a" \
  -F "language=en" \
  -F "mode=docs" \
  -F "prompt_terms=Indus Gaming" \
  -F "prompt_terms=Wispr Flow"
```

Health check:

```bash
curl -sS http://127.0.0.1:8000/healthz
```

## Docker

Build and run:

```bash
cd cloud
docker build -t dicta-cloud .
docker run --rm -p 8000:8000 \
  -e ASR_BACKEND=faster_whisper \
  -e MODEL_SIZE=small.en \
  -e DEVICE=cpu \
  -e SQLITE_PATH=/app/data/dicta_cloud.sqlite3 \
  -v "$PWD/data:/app/data" \
  dicta-cloud
```

`ffmpeg` is installed in the container. `faster-whisper` will download models on first use unless they already exist in the image/runtime cache.

## Deploy notes

This layout is deployable to a single container target (Fly.io, Render, Railway, ECS, Cloud Run, etc.):
- persistent volume or managed disk for `SQLITE_PATH`
- CPU is fine for `small.en`; use GPU only if you need higher throughput
- front with HTTPS and set request size/time limits at the proxy layer
- rotate API keys by issuing new ones and disabling old hashes in sqlite

## Expected behaviors

- Missing/invalid key: `401`
- Rate limited: `429`
- Daily quota exhausted: `429` with `quota_exceeded`
- Oversized/invalid audio: `400`
- ASR backend failure: `502`
