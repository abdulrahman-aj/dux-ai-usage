"""Threshold-crossing and 429-reuse behavior (the toast rules)."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "DuxAiUsage", "collectors"))

from model import clamp_thresholds, compute_events, merge_rate_limited


def _providers(specs):
    """specs: [(providerId, windowId, percent, resetsAt)] -> provider list."""
    grouped = {}
    for provider_id, window_id, percent, resets_at in specs:
        grouped.setdefault(provider_id, []).append({
            "id": window_id, "label": window_id,
            "usedPercent": percent, "resetsAt": resets_at})
    return [{"id": pid, "name": pid, "plan": "", "stale": False,
             "windows": windows, "resets": None, "error": None}
            for pid, windows in grouped.items()]


def test_first_crossing_fires_warn_once_then_crit():
    curr = _providers([("claude", "fiveHour", 85.0, "R1")])
    events, notified = compute_events([], curr, {}, 80, 100)
    assert [e["level"] for e in events] == ["warn"]
    assert notified == {"claude/fiveHour": "warn"}
    # Same poll again: no repeat.
    events, notified = compute_events(
        curr, curr, notified, 80, 100)
    assert events == []
    # Rising to crit fires once.
    higher = _providers([("claude", "fiveHour", 100.0, "R1")])
    events, notified = compute_events(curr, higher, notified, 80, 100)
    assert [e["level"] for e in events] == ["crit"]


def test_recovery_rearms_and_reset_period_clears():
    curr = _providers([("codex", "weekly", 100.0, "R1")])
    _, notified = compute_events([], curr, {}, 80, 100)
    assert notified == {"codex/weekly": "crit"}
    # Drop below warn: re-armed silently.
    low = _providers([("codex", "weekly", 10.0, "R1")])
    events, notified = compute_events(curr, low, notified, 80, 100)
    assert events == [] and notified == {}
    # Exhaust again, then the period rolls: one reset event, re-armed.
    _, notified = compute_events(low, curr, notified, 80, 100)
    rolled = _providers([("codex", "weekly", 5.0, "R2")])
    events, notified = compute_events(curr, rolled, notified, 80, 100)
    assert [e["level"] for e in events] == ["reset"]
    assert notified == {}


def test_reset_event_opt_out_and_non_exhausted_roll_silent():
    prev = _providers([("go", "weekly", 90.0, "R1")])
    _, notified = compute_events([], prev, {}, 80, 100)
    rolled = _providers([("go", "weekly", 4.0, "R2")])
    events, _ = compute_events(prev, rolled, notified, 80, 100,
                               reset_notify=False)
    assert events == []
    # Warn-level (not exhausted) roll is silent even with reset_notify on.
    events, notified = compute_events(prev, rolled, notified, 80, 100)
    assert events == [] and notified == {}


def test_disabled_providers_skipped_and_dropped():
    curr = _providers([("claude", "fiveHour", 99.0, "R1")])
    events, notified = compute_events([], curr, {}, 80, 100,
                                      disabled={"claude"})
    assert events == [] and notified == {}
    stale = {"claude/fiveHour": "warn"}
    _, notified = compute_events([], curr, stale, 80, 100,
                                 disabled={"claude"})
    assert notified == {}


def test_inverted_thresholds_clamped():
    assert clamp_thresholds(90, 80) == (90.0, 91.0)
    curr = _providers([("go", "monthly", 90.5, "R1")])
    events, _ = compute_events([], curr, {}, 90, 80)
    assert [e["level"] for e in events] == ["warn"]


def test_rate_limited_keeps_last_known_values():
    prev = _providers([("claude", "fiveHour", 17.0, "R1")])
    fresh = [{"id": "claude", "name": "Claude", "plan": "Pro",
              "stale": False, "windows": [], "resets": None,
              "error": {"kind": "rateLimited", "hint": "retry"}}]
    merged, limited = merge_rate_limited(fresh, prev)
    assert limited == ["claude"]
    assert merged[0]["windows"][0]["usedPercent"] == 17.0
    assert merged[0]["stale"] is True
    # Non-429 errors pass through untouched.
    auth = [{"id": "codex", "error": {"kind": "auth", "hint": "login"}}]
    merged, limited = merge_rate_limited(auth, prev)
    assert merged == auth and limited == []
