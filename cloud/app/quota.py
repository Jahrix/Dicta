from __future__ import annotations

from dataclasses import dataclass

from fastapi import HTTPException, Request

from .auth import AuthenticatedKey
from .storage import QuotaExceededError, QuotaSnapshot, release_reserved_quota, reserve_daily_quota


@dataclass(frozen=True)
class ReservedQuota:
    snapshot: QuotaSnapshot
    reserved_seconds: int


def reserve_quota_or_raise(request: Request, auth_key: AuthenticatedKey, audio_seconds: int) -> ReservedQuota:
    try:
        snapshot = reserve_daily_quota(auth_key.key_hash, audio_seconds)
    except QuotaExceededError as exc:
        raise HTTPException(
            status_code=429,
            detail={
                "error": "quota_exceeded",
                "message": "Daily quota exceeded",
                "quota_minutes": exc.quota_seconds // 60,
                "used_minutes": exc.used_seconds / 60,
                "requested_minutes": exc.requested_seconds / 60,
                "request_id": getattr(request.state, "request_id", None),
            },
        ) from exc

    return ReservedQuota(snapshot=snapshot, reserved_seconds=audio_seconds)


def release_quota(auth_key: AuthenticatedKey, reservation: ReservedQuota | None) -> None:
    if reservation is None:
        return
    release_reserved_quota(auth_key.key_hash, reservation.reserved_seconds)
