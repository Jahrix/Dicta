from __future__ import annotations

import argparse
import hashlib
import secrets
import sqlite3
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path
from typing import Iterable

from .settings import get_settings


SCHEMA_STATEMENTS: tuple[str, ...] = (
    """
    CREATE TABLE IF NOT EXISTS api_keys (
        key_hash TEXT PRIMARY KEY,
        label TEXT NOT NULL,
        created_at TEXT NOT NULL,
        enabled INTEGER NOT NULL DEFAULT 1,
        quota_minutes INTEGER NOT NULL DEFAULT 60
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS daily_usage (
        key_hash TEXT NOT NULL,
        usage_date TEXT NOT NULL,
        audio_seconds_used INTEGER NOT NULL DEFAULT 0,
        request_count INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (key_hash, usage_date),
        FOREIGN KEY (key_hash) REFERENCES api_keys(key_hash) ON DELETE CASCADE
    )
    """,
    "CREATE INDEX IF NOT EXISTS idx_daily_usage_key_date ON daily_usage(key_hash, usage_date)",
)


@dataclass(frozen=True)
class APIKeyRecord:
    key_hash: str
    label: str
    created_at: str
    enabled: bool
    quota_minutes: int


@dataclass(frozen=True)
class QuotaSnapshot:
    usage_date: str
    used_seconds: int
    quota_seconds: int
    remaining_seconds: int


class QuotaExceededError(Exception):
    def __init__(self, *, used_seconds: int, requested_seconds: int, quota_seconds: int, usage_date: str) -> None:
        self.used_seconds = used_seconds
        self.requested_seconds = requested_seconds
        self.quota_seconds = quota_seconds
        self.usage_date = usage_date
        super().__init__(
            f"Daily quota exceeded for {usage_date}: used {used_seconds}s, requested {requested_seconds}s, quota {quota_seconds}s"
        )


class StorageError(Exception):
    pass


class KeyNotFoundError(StorageError):
    pass


class KeyDisabledError(StorageError):
    pass


def utc_now() -> datetime:
    return datetime.now(tz=UTC)


def usage_date_utc() -> str:
    return utc_now().date().isoformat()


def ensure_db_path(db_path: Path) -> None:
    db_path.parent.mkdir(parents=True, exist_ok=True)


def connect(db_path: Path) -> sqlite3.Connection:
    ensure_db_path(db_path)
    conn = sqlite3.connect(db_path, timeout=30, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db(db_path: Path | None = None) -> None:
    path = db_path or get_settings().sqlite_path
    with connect(path) as conn:
        for statement in SCHEMA_STATEMENTS:
            conn.execute(statement)


def hash_api_key(raw_key: str) -> str:
    return hashlib.sha256(raw_key.encode("utf-8")).hexdigest()


def get_api_key_by_hash(key_hash: str, db_path: Path | None = None) -> APIKeyRecord | None:
    path = db_path or get_settings().sqlite_path
    with connect(path) as conn:
        row = conn.execute(
            "SELECT key_hash, label, created_at, enabled, quota_minutes FROM api_keys WHERE key_hash = ?",
            (key_hash,),
        ).fetchone()
    if row is None:
        return None
    return APIKeyRecord(
        key_hash=row["key_hash"],
        label=row["label"],
        created_at=row["created_at"],
        enabled=bool(row["enabled"]),
        quota_minutes=int(row["quota_minutes"]),
    )


def get_api_key_by_raw_key(raw_key: str, db_path: Path | None = None) -> APIKeyRecord | None:
    return get_api_key_by_hash(hash_api_key(raw_key), db_path=db_path)


def create_api_key(label: str, quota_minutes: int, db_path: Path | None = None) -> tuple[str, APIKeyRecord]:
    path = db_path or get_settings().sqlite_path
    init_db(path)
    raw_key = f"dicta_{secrets.token_urlsafe(32)}"
    key_hash = hash_api_key(raw_key)
    created_at = utc_now().isoformat()
    record = APIKeyRecord(
        key_hash=key_hash,
        label=label,
        created_at=created_at,
        enabled=True,
        quota_minutes=quota_minutes,
    )
    with connect(path) as conn:
        conn.execute(
            "INSERT INTO api_keys(key_hash, label, created_at, enabled, quota_minutes) VALUES (?, ?, ?, 1, ?)",
            (record.key_hash, record.label, record.created_at, record.quota_minutes),
        )
    return raw_key, record


def reserve_daily_quota(key_hash: str, requested_seconds: int, db_path: Path | None = None) -> QuotaSnapshot:
    path = db_path or get_settings().sqlite_path
    today = usage_date_utc()
    updated_at = utc_now().isoformat()

    with connect(path) as conn:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute(
            """
            SELECT api_keys.enabled, api_keys.quota_minutes, COALESCE(daily_usage.audio_seconds_used, 0) AS used_seconds
            FROM api_keys
            LEFT JOIN daily_usage ON daily_usage.key_hash = api_keys.key_hash AND daily_usage.usage_date = ?
            WHERE api_keys.key_hash = ?
            """,
            (today, key_hash),
        ).fetchone()
        if row is None:
            raise KeyNotFoundError("Unknown API key")
        if not bool(row["enabled"]):
            raise KeyDisabledError("API key is disabled")

        used_seconds = int(row["used_seconds"])
        quota_seconds = int(row["quota_minutes"]) * 60
        if used_seconds + requested_seconds > quota_seconds:
            raise QuotaExceededError(
                used_seconds=used_seconds,
                requested_seconds=requested_seconds,
                quota_seconds=quota_seconds,
                usage_date=today,
            )

        conn.execute(
            """
            INSERT INTO daily_usage(key_hash, usage_date, audio_seconds_used, request_count, updated_at)
            VALUES (?, ?, ?, 1, ?)
            ON CONFLICT(key_hash, usage_date)
            DO UPDATE SET
                audio_seconds_used = daily_usage.audio_seconds_used + excluded.audio_seconds_used,
                request_count = daily_usage.request_count + 1,
                updated_at = excluded.updated_at
            """,
            (key_hash, today, requested_seconds, updated_at),
        )
        final_used_seconds = used_seconds + requested_seconds
        conn.commit()

    return QuotaSnapshot(
        usage_date=today,
        used_seconds=final_used_seconds,
        quota_seconds=quota_seconds,
        remaining_seconds=max(quota_seconds - final_used_seconds, 0),
    )


def release_reserved_quota(key_hash: str, released_seconds: int, db_path: Path | None = None) -> None:
    if released_seconds <= 0:
        return

    path = db_path or get_settings().sqlite_path
    today = usage_date_utc()
    updated_at = utc_now().isoformat()

    with connect(path) as conn:
        conn.execute("BEGIN IMMEDIATE")
        row = conn.execute(
            "SELECT audio_seconds_used, request_count FROM daily_usage WHERE key_hash = ? AND usage_date = ?",
            (key_hash, today),
        ).fetchone()
        if row is None:
            return

        used_seconds = max(int(row["audio_seconds_used"]) - released_seconds, 0)
        request_count = max(int(row["request_count"]) - 1, 0)
        conn.execute(
            """
            UPDATE daily_usage
            SET audio_seconds_used = ?, request_count = ?, updated_at = ?
            WHERE key_hash = ? AND usage_date = ?
            """,
            (used_seconds, request_count, updated_at, key_hash, today),
        )
        conn.commit()


def iter_api_keys(db_path: Path | None = None) -> Iterable[APIKeyRecord]:
    path = db_path or get_settings().sqlite_path
    with connect(path) as conn:
        rows = conn.execute(
            "SELECT key_hash, label, created_at, enabled, quota_minutes FROM api_keys ORDER BY created_at ASC"
        ).fetchall()
    for row in rows:
        yield APIKeyRecord(
            key_hash=row["key_hash"],
            label=row["label"],
            created_at=row["created_at"],
            enabled=bool(row["enabled"]),
            quota_minutes=int(row["quota_minutes"]),
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Dicta cloud storage admin")
    parser.add_argument("--db-path", default=str(get_settings().sqlite_path), help="SQLite database path")
    subparsers = parser.add_subparsers(dest="command", required=True)

    init_parser = subparsers.add_parser("init-db", help="Initialize the sqlite database")
    init_parser.set_defaults(command_name="init-db")

    create_key_parser = subparsers.add_parser("create-key", help="Create a new API key")
    create_key_parser.add_argument("--label", required=True, help="Human-readable label for the key")
    create_key_parser.add_argument("--quota-minutes", type=int, default=60, help="Daily quota in audio minutes")
    create_key_parser.set_defaults(command_name="create-key")

    list_keys_parser = subparsers.add_parser("list-keys", help="List stored API keys")
    list_keys_parser.set_defaults(command_name="list-keys")

    return parser


def main() -> None:
    parser = build_parser()
    args = parser.parse_args()
    db_path = Path(args.db_path).expanduser()

    if args.command == "init-db":
        init_db(db_path)
        print(f"Initialized database at {db_path}")
        return

    if args.command == "create-key":
        raw_key, record = create_api_key(args.label, args.quota_minutes, db_path=db_path)
        print(f"Created API key for {record.label}")
        print(f"Quota minutes/day: {record.quota_minutes}")
        print(f"Raw key (shown once): {raw_key}")
        return

    if args.command == "list-keys":
        init_db(db_path)
        for record in iter_api_keys(db_path):
            print(
                f"label={record.label} enabled={record.enabled} quota_minutes={record.quota_minutes} created_at={record.created_at} key_hash={record.key_hash}"
            )
        return

    parser.error(f"Unsupported command: {args.command}")


if __name__ == "__main__":
    main()
