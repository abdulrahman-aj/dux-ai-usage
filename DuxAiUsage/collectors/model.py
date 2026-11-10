"""Normalized usage document and threshold-crossing events.

Pure functions over plain data so behavior is unit-testable. The QML
daemon shells out to collect.py (which uses this module) instead of
reimplementing the rules, keeping a single implementation.

Document shape emitted by collect.py::

    {"fetchedAt": str, "providers": [provider...],
     "events": [event...], "notified": {key: level}, "limited": [providerId...]}

provider::

    {"id": str, "name": str, "plan": str, "stale": bool,
     "staleSince": str | None, "headlineId": str | None,
     "usageUrl": str | None,
     "windows": [{"id": str, "label": str,
                  "usedPercent": float | None, "resetsAt": str | None}],
     "resets": {"available": int, "url": str} | None,
     "error": {"kind": str, "hint": str} | None}

headlineId names the window the pill and cards headline (see
headline_window); staleSince is the fetch the last-known values came
from, so the stale tag shows only for 429-kept values, with its age.
usageUrl is the provider usage page behind the quiet open link.

event::

    {"level": "warn" | "crit" | "reset", "providerId": str,
     "providerName": str, "windowId": str, "windowLabel": str,
     "usedPercent": float | None}
"""

RANK = {"warn": 1, "crit": 2}

# Headline window rule (pill + card glance): per provider the pill shows
# ONE number. Default is the long window; a shorter window that reaches
# the warning threshold takes over so a burning 5-hour window is not
# hidden behind a calm weekly one. Weekly-scoped per-model rows
# ("weekly-<model>") are detail rows only, never the headline.
LONG_WINDOW = {"claude": "weekly", "codex": "weekly", "opencodeGo": "monthly"}

# Short -> long ordering for headline comparison.
_WINDOW_RANK = {"fiveHour": 0, "rolling": 0, "weekly": 1, "monthly": 2}


def _window_rank(window_id):
    """Rank a window id short -> long for headline comparison.

    Why ranks, not durations: Codex reports durations but Claude/Go do
    not, so ids are the only stable ordering key. Unknown ids rank as
    weekly (never shorter than a long window) so a future window kind
    cannot hijack the pill.
    """
    if isinstance(window_id, str):
        if window_id in _WINDOW_RANK:
            return _WINDOW_RANK[window_id]
        if window_id.startswith("w"):
            try:
                mins = int(window_id[1:])
            except ValueError:
                pass
            else:
                if mins <= 300:
                    return 0
                if mins <= 10080:
                    return 1
                return 2
    return 1


def _is_scoped(window_id):
    return isinstance(window_id, str) and window_id.startswith("weekly-")


def _numeric_percent(window):
    percent = window.get("usedPercent") if isinstance(window, dict) else None
    if isinstance(percent, bool) or not isinstance(percent, (int, float)):
        return None
    return float(percent)


def clamp_thresholds(warn, crit):
    """Return (warn, crit) with crit strictly above warn.

    Why: two independent settings sliders can end up equal or inverted;
    without this the warn band would be unreachable.
    """
    warn = float(warn)
    crit = float(crit)
    if crit <= warn:
        crit = warn + 1.0
    return warn, crit


def level_of(percent, warn, crit):
    """Return 'crit', 'warn' or 'ok' for a numeric percentage."""
    if percent is None:
        return "ok"
    if percent >= crit:
        return "crit"
    if percent >= warn:
        return "warn"
    return "ok"


def _window_map(providers):
    """Index {providerId: {windowId: window}} for fast lookup."""
    out = {}
    for provider in providers or []:
        windows = {}
        for window in provider.get("windows") or []:
            if isinstance(window, dict) and window.get("id"):
                windows[window["id"]] = window
        out[provider.get("id")] = windows
    return out


def _provider_name(providers, provider_id):
    for provider in providers or []:
        if provider.get("id") == provider_id:
            return provider.get("name") or provider_id
    return provider_id


def compute_events(
    prev_providers, curr_providers, notified, warn, crit, disabled=(), reset_notify=True
):
    """Compare snapshots, returning (events, new_notified).

    Rules: an event fires once per window per upward crossing
    (ok->warn, warn->crit, ok->crit). Dropping below warn re-arms the
    window. A changed resetsAt means a new period: notified state is
    cleared, and an exhausted (crit-notified) window emits a "reset"
    event when reset_notify is on. Disabled providers are skipped and
    their notified state is dropped so re-enabling re-arms them.
    """
    warn, crit = clamp_thresholds(warn, crit)
    disabled = set(disabled or ())
    prev = _window_map(prev_providers)
    curr = _window_map(curr_providers)
    notified = dict(notified or {})
    events = []

    for provider_id, windows in curr.items():
        if provider_id in disabled:
            continue
        old_windows = prev.get(provider_id, {})
        name = _provider_name(curr_providers, provider_id)
        for window_id, window in windows.items():
            key = provider_id + "/" + window_id
            percent = window.get("usedPercent")
            if isinstance(percent, bool) or not isinstance(percent, (int, float)):
                continue
            percent = float(percent)
            old = old_windows.get(window_id, {})
            old_reset = old.get("resetsAt")
            new_reset = window.get("resetsAt")
            if old_reset and new_reset and old_reset != new_reset:
                if notified.pop(key, None) == "crit" and reset_notify:
                    events.append(
                        {
                            "level": "reset",
                            "providerId": provider_id,
                            "providerName": name,
                            "windowId": window_id,
                            "windowLabel": window.get("label") or window_id,
                            "usedPercent": percent,
                        }
                    )
                # New period below: fall through to level check with no
                # notified state so a still-high window re-fires once.
            rank = RANK.get(level_of(percent, warn, crit), 0)
            if rank == 0:
                notified.pop(key, None)
                continue
            if rank > RANK.get(notified.get(key), 0):
                level = "crit" if rank == 2 else "warn"
                notified[key] = level
                events.append(
                    {
                        "level": level,
                        "providerId": provider_id,
                        "providerName": name,
                        "windowId": window_id,
                        "windowLabel": window.get("label") or window_id,
                        "usedPercent": percent,
                    }
                )

    for key in [k for k in notified if k.split("/")[0] in disabled]:
        del notified[key]
    return events, notified


def window_visible(window):
    """True unless this is a hidden per-model row.

    Claude weekly-scoped rows ("Weekly · Fable") show only once used
    above 0%: at 0% they are noise, and the pill headline never uses
    them. Every main window is always visible.
    """
    if not isinstance(window, dict):
        return False
    if _is_scoped(window.get("id")):
        percent = _numeric_percent(window)
        return percent is not None and percent > 0
    return True


def visible_windows(provider):
    """Windows of a provider minus hidden per-model rows (new list)."""
    if not isinstance(provider, dict):
        return []
    return [w for w in (provider.get("windows") or []) if window_visible(w)]


def headline_window(provider, warn, crit):
    """Return the window dict the pill/cards headline, or None.

    Default is the provider's long window (LONG_WINDOW). A shorter
    window at/above warn takes over, so urgency wins over the default;
    a short warn never hides a long crit. Ties between short windows
    break by higher percent, then shorter window, then id.
    """
    if not isinstance(provider, dict):
        return None
    warn, crit = clamp_thresholds(warn, crit)
    order = {"ok": 0, "warn": 1, "crit": 2}
    candidates = []
    for window in provider.get("windows") or []:
        if not isinstance(window, dict) or _is_scoped(window.get("id")):
            continue
        percent = _numeric_percent(window)
        if percent is None:
            continue
        candidates.append((window, percent))
    if not candidates:
        return None
    long_id = LONG_WINDOW.get(provider.get("id"))
    long = next((w for w, _ in candidates if w.get("id") == long_id), None)
    long_rank = _window_rank(long_id)
    long_level = order.get(level_of(_numeric_percent(long), warn, crit), 0)

    def short_key(item):
        window, percent = item
        return (
            order.get(level_of(percent, warn, crit), 0),
            percent,
            -_window_rank(window.get("id")),
            str(window.get("id")),
        )

    short_warnings = [
        item
        for item in candidates
        if _window_rank(item[0].get("id")) < long_rank
        and order.get(level_of(item[1], warn, crit), 0) >= 1
        and order.get(level_of(item[1], warn, crit), 0) >= long_level
    ]
    if short_warnings:
        return sorted(short_warnings, key=short_key)[-1][0]
    if long is not None:
        return long
    return sorted(candidates, key=lambda item: (item[1], str(item[0].get("id"))))[-1][0]


def merge_rate_limited(fresh_providers, prev_providers, prev_fetched_at=None):
    """Keep last-known windows for providers hit by HTTP 429.

    Returns (merged_providers, limited_ids). A fresh provider whose
    error kind is "rateLimited" is replaced by its previous snapshot
    with stale=True (keeping the original staleSince fetch time so
    surfaces can say how old the values are); every other fresh
    provider is kept as-is with any stale marker cleared.
    """
    prev = {p.get("id"): p for p in (prev_providers or []) if isinstance(p, dict)}
    merged = []
    limited = []
    for provider in fresh_providers or []:
        error = provider.get("error") or {}
        old = prev.get(provider.get("id"))
        if (
            error.get("kind") == "rateLimited"
            and isinstance(old, dict)
            and old.get("windows")
            and not (old.get("error") or {}).get("kind")
        ):
            kept = dict(old)
            kept["stale"] = True
            kept["staleSince"] = old.get("staleSince") or prev_fetched_at
            merged.append(kept)
            limited.append(provider.get("id"))
        else:
            merged.append(provider)
    return merged, limited
