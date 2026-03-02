from __future__ import annotations

from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from .storage import APIKeyRecord, get_api_key_by_raw_key


bearer_scheme = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class AuthenticatedKey:
    key_hash: str
    label: str
    quota_minutes: int


async def require_api_key(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(bearer_scheme),
) -> AuthenticatedKey:
    if credentials is None or credentials.scheme.lower() != "bearer" or not credentials.credentials.strip():
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "unauthorized", "message": "Missing bearer API key", "request_id": getattr(request.state, "request_id", None)},
            headers={"WWW-Authenticate": "Bearer"},
        )

    record = get_api_key_by_raw_key(credentials.credentials.strip())
    if record is None or not record.enabled:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail={"error": "unauthorized", "message": "Invalid or disabled API key", "request_id": getattr(request.state, "request_id", None)},
            headers={"WWW-Authenticate": "Bearer"},
        )

    request.state.api_key_hash = record.key_hash
    request.state.api_key_label = record.label
    request.state.api_key_quota_minutes = record.quota_minutes
    return AuthenticatedKey(key_hash=record.key_hash, label=record.label, quota_minutes=record.quota_minutes)
