"""collect.py scheduling: Claude-specific minimum interval (per-provider debounce)."""

import io
import json
import os
import sys
from contextlib import redirect_stdout

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "DuxAiUsage", "collectors")
)

import collect


def _run_collect(argv):
    buf = io.StringIO()
    with redirect_stdout(buf):
        assert collect.main(argv) == 0
    return json.loads(buf.getvalue())


def _prev_snapshot(updated_at, fetched_at):
    return json.dumps(
        {
            "fetchedAt": fetched_at,
            "providers": [
                {
                    "id": "claude",
                    "name": "Claude",
                    "plan": "Pro",
                    "stale": False,
                    "updatedAt": updated_at,
                    "windows": [
                        {
                            "id": "fiveHour",
                            "label": "5-hour",
                            "usedPercent": 17.0,
                            "resetsAt": None,
                        }
                    ],
                    "resets": None,
                    "error": None,
                    "headlineId": "fiveHour",
                    "headlineShort": False,
                }
            ],
        }
    )


def test_recent_claude_is_reused_without_refetch():
    # 5 minutes after the last good Claude fetch with a 10-minute minimum:
    # no network reader runs (Codex/Go disabled), the snapshot keeps the
    # previous windows with their own updatedAt, and nothing is limited.
    doc = _run_collect(
        [
            "--disable",
            "codex,opencodeGo",
            "--prev",
            _prev_snapshot("2026-11-10T20:00:00Z", "2026-11-10T20:00:00Z"),
            "--now",
            "2026-11-10T20:05:00Z",
        ]
    )
    assert doc["fetchedAt"] == "2026-11-10T20:05:00Z"
    assert doc["limited"] == []
    (claude,) = doc["providers"]
    assert claude["windows"][0]["usedPercent"] == 17.0
    assert claude["updatedAt"] == "2026-11-10T20:00:00Z"
    assert claude.get("stale") is False


def test_stale_claude_is_due_again():
    # 30 minutes later the minimum has elapsed: the collector must call
    # the Claude reader again instead of reusing (patched: no network).
    import collect as _collect

    seen = []

    def spy(*args, **kwargs):
        seen.append(True)
        return {
            "id": "claude",
            "name": "Claude",
            "plan": "Pro",
            "stale": False,
            "windows": [
                {
                    "id": "fiveHour",
                    "label": "5-hour",
                    "usedPercent": 42.0,
                    "resetsAt": None,
                }
            ],
            "resets": None,
            "usageUrl": "https://claude.ai/settings/usage",
            "error": None,
        }

    real_readers = _collect.READERS
    _collect.READERS = tuple(
        (pid, spy if pid == "claude" else fn) for pid, fn in real_readers
    )
    try:
        doc = _run_collect(
            [
                "--disable",
                "codex,opencodeGo",
                "--prev",
                _prev_snapshot("2026-11-10T20:00:00Z", "2026-11-10T20:00:00Z"),
                "--now",
                "2026-11-10T20:30:00Z",
            ]
        )
    finally:
        _collect.READERS = real_readers
    assert seen, "due Claude must be refetched, not reused"
    (claude,) = doc["providers"]
    assert claude["windows"][0]["usedPercent"] == 42.0
    assert claude["updatedAt"] == "2026-11-10T20:30:00Z"


def _prev_rate_limited(updated_at, fetched_at, retry_after_sec=None):
    """Prev snapshot whose last Claude attempt hit 429 (kept values)."""
    provider = {
        "id": "claude",
        "name": "Claude",
        "plan": "Pro",
        "stale": True,
        "staleSince": updated_at,
        "updatedAt": updated_at,
        "rateLimited": True,
        "windows": [
            {
                "id": "fiveHour",
                "label": "5-hour",
                "usedPercent": 17.0,
                "resetsAt": None,
            }
        ],
        "resets": None,
        "error": None,
        "headlineId": "fiveHour",
        "headlineShort": False,
    }
    if retry_after_sec is not None:
        provider["retryAfterSec"] = retry_after_sec
    return json.dumps({"fetchedAt": fetched_at, "providers": [provider]})


def _patch_readers(monkey_spy):
    """Swap collect.READERS' claude entry for a spy; return restore fn."""
    import collect as _collect

    real_readers = _collect.READERS
    _collect.READERS = tuple(
        (pid, monkey_spy if pid == "claude" else fn) for pid, fn in real_readers
    )
    return lambda: setattr(_collect, "READERS", real_readers)


def _rate_limited_fresh(retry_after=0):
    return {
        "id": "claude",
        "name": "Claude",
        "plan": "Pro",
        "stale": False,
        "windows": [],
        "resets": None,
        "usageUrl": "https://claude.ai/settings/usage",
        "error": {"kind": "rateLimited", "hint": "retry", "retryAfter": retry_after},
    }


def test_rate_limited_claude_skips_refetch_within_minimum():
    # Last attempt hit 429 five minutes ago with retry-after 0: no network
    # reader runs (Codex/Go disabled), the kept values stay with their
    # own updatedAt, and nothing is reported as newly limited.
    seen = []

    def spy(*args, **kwargs):
        seen.append(True)
        return _rate_limited_fresh()

    restore = _patch_readers(spy)
    try:
        doc = _run_collect(
            [
                "--disable",
                "codex,opencodeGo",
                "--prev",
                _prev_rate_limited("2026-11-10T20:00:00Z", "2026-11-10T20:25:00Z", 0),
                "--now",
                "2026-11-10T20:30:00Z",
            ]
        )
    finally:
        restore()
    assert not seen, "recent 429 must not be retried yet"
    assert doc["fetchedAt"] == "2026-11-10T20:30:00Z"
    assert doc["limited"] == []
    (claude,) = doc["providers"]
    assert claude["windows"][0]["usedPercent"] == 17.0
    assert claude["updatedAt"] == "2026-11-10T20:00:00Z"
    assert claude["stale"] is True and claude["rateLimited"] is True


def test_rate_limited_claude_refetch_due_after_minimum():
    # Fifteen minutes after the 429 attempt the minimum has elapsed: the
    # collector tries again, and the fresh 429 keeps the last-known values.
    seen = []

    def spy(*args, **kwargs):
        seen.append(True)
        return _rate_limited_fresh()

    restore = _patch_readers(spy)
    try:
        doc = _run_collect(
            [
                "--disable",
                "codex,opencodeGo",
                "--prev",
                _prev_rate_limited("2026-11-10T20:00:00Z", "2026-11-10T20:00:00Z", 0),
                "--now",
                "2026-11-10T20:15:00Z",
            ]
        )
    finally:
        restore()
    assert seen, "due Claude must be retried, not skipped"
    assert doc["limited"] == ["claude"]
    (claude,) = doc["providers"]
    assert claude["windows"][0]["usedPercent"] == 17.0
    assert claude["stale"] is True and claude["rateLimited"] is True
    assert claude["updatedAt"] == "2026-11-10T20:00:00Z"


def test_rate_limited_retry_after_hint_extends_wait():
    # A served Retry-After above the minimum (30 min) holds the skip past
    # the 10-minute floor; once it elapses the collector retries.
    seen = []

    def spy(*args, **kwargs):
        seen.append(True)
        return _rate_limited_fresh(retry_after=1800)

    restore = _patch_readers(spy)
    try:
        doc = _run_collect(
            [
                "--disable",
                "codex,opencodeGo",
                "--prev",
                _prev_rate_limited(
                    "2026-11-10T20:00:00Z", "2026-11-10T20:15:00Z", 1800
                ),
                "--now",
                "2026-11-10T20:30:00Z",
            ]
        )
        assert not seen, "Retry-After hint must hold the skip"
        assert doc["limited"] == []
        doc = _run_collect(
            [
                "--disable",
                "codex,opencodeGo",
                "--prev",
                _prev_rate_limited(
                    "2026-11-10T20:00:00Z", "2026-11-10T20:00:00Z", 1800
                ),
                "--now",
                "2026-11-10T20:35:00Z",
            ]
        )
    finally:
        restore()
    assert seen, "elapsed Retry-After must retry"
