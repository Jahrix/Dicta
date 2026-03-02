from __future__ import annotations

from fastapi import Request
from slowapi import Limiter
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address
from starlette.responses import JSONResponse

from .storage import hash_api_key


limiter = Limiter(key_func=get_remote_address, headers_enabled=True)


def api_key_rate_limit_key(request: Request) -> str:
    authorization = request.headers.get("Authorization", "")
    if authorization.lower().startswith("bearer "):
        raw_key = authorization.split(" ", 1)[1].strip()
        if raw_key:
            return f"api-key:{hash_api_key(raw_key)}"
    return f"anon:{get_remote_address(request)}"


async def rate_limit_exceeded_handler(request: Request, exc: RateLimitExceeded) -> JSONResponse:
    return JSONResponse(
        status_code=429,
        content={
            "error": "rate_limit_exceeded",
            "message": str(exc.detail),
            "request_id": getattr(request.state, "request_id", None),
        },
    )
