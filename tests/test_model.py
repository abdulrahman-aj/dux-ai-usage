"""Threshold-crossing and 429-reuse behavior (the toast rules)."""

import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "DuxAiUsage", "collectors")
)

from model import (
    clamp_thresholds,
    compute_events,
    headline_window,
    merge_rate_limited,
    visible_windows,
    window_visible,
)


def _providers(specs):
    """specs: [(providerId, windowId, percent, resetsAt)] -> provider list."""
    grouped = {}
    for provider_id, window_id, percent, resets_at in specs:
        grouped.setdefault(provider_id, []).append(
            {
                "id": window_id,
                "label": window_id,
                "usedPercent": percent,
                "resetsAt": resets_at,
            }
        )
    return [
        {
            "id": pid,
            "name": pid,
            "plan": "",
            "stale": False,
            "windows": windows,
            "resets": None,
            "error": None,
        }
        for pid, windows in grouped.items()
    ]


def test_first_crossing_fires_warn_once_then_crit():
    curr = _providers([("claude", "fiveHour", 85.0, "R1")])
    events, notified = compute_events([], curr, {}, 80, 100)
    assert [e["level"] for e in events] == ["warn"]
    assert notified == {"claude/fiveHour": "warn"}
    # Same poll again: no repeat.
    events, notified = compute_events(curr, curr, notified, 80, 100)
    assert events == []
    # Rising to crit fires once.
    higher = _providers([("claude", "fiveHour", 100.0, "R1")])
    events, notified = compute_events(curr, higher, notified, 80, 100)
    assert [e["level"] for e in events] == ["crit"]


def test_recovery_rearms_and_reset_period_clears():
    curr = _providers([("codex", "weekly", 100.0, "R1")])
    _, notified = compute_events([], curr, {}, 80, 100)
    assert notified == {"codex/weekly": "crit"}
    # Drop below warn after crit: one reset event, then re-armed.
    low = _providers([("codex", "weekly", 10.0, "R1")])
    events, notified = compute_events(curr, low, notified, 80, 100)
    assert [e["level"] for e in events] == ["reset"]
    assert notified == {}
    # Exhaust again, then the period rolls: one reset event, re-armed.
    _, notified = compute_events(low, curr, notified, 80, 100)
    rolled = _providers([("codex", "weekly", 5.0, "R2")])
    events, notified = compute_events(curr, rolled, notified, 80, 100)
    assert [e["level"] for e in events] == ["reset"]
    assert notified == {}


def test_moving_resets_at_does_not_refire_warn():
    # Rolling windows (Go) move resetsAt every poll while staying high:
    # warn fires once, not once per poll.
    first = _providers([("opencodeGo", "rolling", 85.0, "T1")])
    events, notified = compute_events([], first, {}, 80, 100)
    assert [e["level"] for e in events] == ["warn"]
    second = _providers([("opencodeGo", "rolling", 85.0, "T2")])
    events, notified = compute_events(first, second, notified, 80, 100)
    assert events == []
    third = _providers([("opencodeGo", "rolling", 85.0, "T3")])
    events, notified = compute_events(second, third, notified, 80, 100)
    assert events == [] and notified == {"opencodeGo/rolling": "warn"}


def test_reset_event_opt_out_and_non_exhausted_roll_silent():
    prev = _providers([("go", "weekly", 90.0, "R1")])
    _, notified = compute_events([], prev, {}, 80, 100)
    rolled = _providers([("go", "weekly", 4.0, "R2")])
    events, _ = compute_events(prev, rolled, notified, 80, 100, reset_notify=False)
    assert events == []
    # Warn-level (not exhausted) roll is silent even with reset_notify on.
    events, notified = compute_events(prev, rolled, notified, 80, 100)
    assert events == [] and notified == {}


def test_disabled_providers_skipped_and_dropped():
    curr = _providers([("claude", "fiveHour", 99.0, "R1")])
    events, notified = compute_events([], curr, {}, 80, 100, disabled={"claude"})
    assert events == [] and notified == {}
    stale = {"claude/fiveHour": "warn"}
    _, notified = compute_events([], curr, stale, 80, 100, disabled={"claude"})
    assert notified == {}


def test_inverted_thresholds_clamped():
    assert clamp_thresholds(90, 80) == (90.0, 91.0)
    curr = _providers([("go", "monthly", 90.5, "R1")])
    events, _ = compute_events([], curr, {}, 90, 80)
    assert [e["level"] for e in events] == ["warn"]


def test_rate_limited_keeps_last_known_values():
    prev = _providers([("claude", "fiveHour", 17.0, "R1")])
    fresh = [
        {
            "id": "claude",
            "name": "Claude",
            "plan": "Pro",
            "stale": False,
            "windows": [],
            "resets": None,
            "error": {"kind": "rateLimited", "hint": "retry"},
        }
    ]
    merged, limited = merge_rate_limited(fresh, prev)
    assert limited == ["claude"]
    assert merged[0]["windows"][0]["usedPercent"] == 17.0
    assert merged[0]["stale"] is True
    # Auth errors pass through untouched.
    auth = [{"id": "codex", "error": {"kind": "auth", "hint": "login"}}]
    merged, limited = merge_rate_limited(auth, prev)
    assert merged == auth and limited == []
    # Unreachable providers keep last-known values too, but without
    # backoff: they retry on the normal schedule.
    down = [
        {
            "id": "claude",
            "name": "Claude",
            "plan": "Pro",
            "stale": False,
            "windows": [],
            "resets": None,
            "error": {"kind": "unavailable", "hint": "retry"},
        }
    ]
    merged, limited = merge_rate_limited(down, prev)
    assert merged[0]["windows"][0]["usedPercent"] == 17.0
    assert merged[0]["stale"] is True and limited == []


def _headlined(provider_id, windows, warn=80, crit=100):
    """Build one provider and return its headline window id (or None)."""
    provider = {
        "id": provider_id,
        "name": provider_id,
        "windows": [
            {"id": wid, "label": wid, "usedPercent": pct, "resetsAt": None}
            for wid, pct in windows
        ],
    }
    headline = headline_window(provider, warn, crit)
    return headline.get("id") if headline else None


def test_headline_defaults_to_long_window():
    assert _headlined("claude", [("fiveHour", 30.0), ("weekly", 4.0)]) == "weekly"
    assert _headlined("codex", [("fiveHour", 8.0), ("weekly", 100.0)]) == "weekly"
    monthly = [("rolling", 19.0), ("weekly", 20.0), ("monthly", 89.0)]
    assert _headlined("opencodeGo", monthly) == "monthly"


def test_short_window_takes_over_at_warning():
    # Calm long window, burning short one: the pill shows the short one.
    assert _headlined("claude", [("fiveHour", 85.0), ("weekly", 4.0)]) == "fiveHour"
    assert (
        _headlined(
            "opencodeGo", [("rolling", 10.0), ("weekly", 91.0), ("monthly", 20.0)]
        )
        == "weekly"
    )
    # Below warn the long window keeps the headline.
    assert _headlined("claude", [("fiveHour", 79.0), ("weekly", 4.0)]) == "weekly"


def test_short_warn_never_hides_long_crit():
    assert _headlined("codex", [("fiveHour", 85.0), ("weekly", 100.0)]) == "weekly"
    # ... but a short crit outranks a long warn.
    assert _headlined("codex", [("fiveHour", 100.0), ("weekly", 85.0)]) == "fiveHour"


def test_headline_ties_and_missing_windows():
    # Two short windows warning: higher percent wins.
    assert (
        _headlined(
            "opencodeGo", [("rolling", 95.0), ("weekly", 91.0), ("monthly", 10.0)]
        )
        == "rolling"
    )
    # Long window absent: worst short warning still takes the headline.
    assert _headlined("claude", [("fiveHour", 90.0)]) == "fiveHour"
    # Long window missing entirely: fall back to the highest window.
    assert _headlined("codex", [("fiveHour", 30.0)]) == "fiveHour"
    assert _headlined("claude", []) is None
    # Scoped per-model rows never headline, however high.
    scoped = [("weekly", 4.0), ("weekly-fable", 99.0), ("fiveHour", 10.0)]
    assert _headlined("claude", scoped) == "weekly"
    # Non-numeric windows are ignored.
    assert _headlined("codex", [("fiveHour", None), ("weekly", 12.0)]) == "weekly"
    assert _headlined("codex", [("fiveHour", None)]) is None


def test_scoped_rows_visible_only_when_used():
    assert window_visible({"id": "weekly", "usedPercent": 0.0}) is True
    assert window_visible({"id": "fiveHour", "usedPercent": 0.0}) is True
    assert window_visible({"id": "weekly-fable", "usedPercent": 0.0}) is False
    assert window_visible({"id": "weekly-fable", "usedPercent": None}) is False
    assert window_visible({"id": "weekly-fable", "usedPercent": 3.0}) is True
    provider = {
        "id": "claude",
        "windows": [
            {"id": "fiveHour", "usedPercent": 30.0},
            {"id": "weekly-fable", "usedPercent": 0.0},
        ],
    }
    assert [w["id"] for w in visible_windows(provider)] == ["fiveHour"]


def test_rate_limited_keeps_stale_since_for_age():
    prev = _providers([("claude", "fiveHour", 17.0, "R1")])
    fresh = [
        {
            "id": "claude",
            "stale": False,
            "windows": [],
            "error": {"kind": "rateLimited", "hint": "retry"},
        }
    ]
    merged, limited = merge_rate_limited(fresh, prev, "2026-11-10T20:00:00Z")
    assert limited == ["claude"]
    assert merged[0]["stale"] is True
    assert merged[0]["staleSince"] == "2026-11-10T20:00:00Z"
    # An already-stale value keeps its original fetch time.
    old = dict(prev[0])
    old["stale"] = True
    old["staleSince"] = "2026-11-10T19:00:00Z"
    merged, _ = merge_rate_limited(fresh, [old], "2026-11-10T20:00:00Z")
    assert merged[0]["staleSince"] == "2026-11-10T19:00:00Z"


def test_vanished_windows_forget_notified_state():
    curr = _providers([("claude", "weekly-fable", 90.0, "R1")])
    _, notified = compute_events([], curr, {}, 80, 100)
    assert notified == {"claude/weekly-fable": "warn"}
    # Scoped row drops to 0% (filtered from the snapshot): state pruned.
    gone = _providers([("claude", "weekly", 4.0, "R1")])
    events, notified = compute_events(curr, gone, notified, 80, 100)
    assert events == [] and notified == {}
    # Reappearing at warn fires again, like a re-arm.
    events, _ = compute_events(gone, curr, notified, 80, 100)
    assert [e["level"] for e in events] == ["warn"]


def test_errored_provider_keeps_notified_state():
    curr = _providers([("codex", "weekly", 90.0, "R1")])
    _, notified = compute_events([], curr, {}, 80, 100)
    assert notified == {"codex/weekly": "warn"}
    # Transient failure (no windows): no events, state survives.
    failed = [
        {
            "id": "codex",
            "name": "codex",
            "error": {"kind": "unavailable", "hint": "retry"},
            "windows": [],
        }
    ]
    events, notified = compute_events(curr, failed, notified, 80, 100)
    assert events == [] and notified == {"codex/weekly": "warn"}
    # Recovery at the same level stays silent; escalation still fires.
    events, notified = compute_events(failed, curr, notified, 80, 100)
    assert events == []
    higher = _providers([("codex", "weekly", 100.0, "R1")])
    events, notified = compute_events(failed, higher, notified, 80, 100)
    assert [e["level"] for e in events] == ["crit"]
