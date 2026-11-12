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
