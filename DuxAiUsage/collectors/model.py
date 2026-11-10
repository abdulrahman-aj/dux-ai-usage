"""Normalized usage document and threshold-crossing events.

Pure functions over plain data so behavior is unit-testable. The QML
daemon shells out to collect.py (which uses this module) instead of
reimplementing the rules, keeping a single implementation.

Document shape emitted by collect.py::

    {"fetchedAt": str, "providers": [provider...],
     "events": [event...], "notified": {key: level}, "limited": [providerId...]}

provider::

    {"id": str, "name": str, "plan": str, "stale": bool,
     "windows": [{"id": str, "label": str,
                  "usedPercent": float | None, "resetsAt": str | None}],
     "resets": {"available": int, "url": str} | None,
     "error": {"kind": str, "hint": str} | None}

event::

    {"level": "warn" | "crit" | "reset", "providerId": str,
     "providerName": str, "windowId": str, "windowLabel": str,
     "usedPercent": float | None}
"""

RANK = {"warn": 1, "crit": 2}


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


def compute_events(prev_providers, curr_providers, notified,
                   warn, crit, disabled=(), reset_notify=True):
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
                    events.append({
                        "level": "reset",
                        "providerId": provider_id,
                        "providerName": name,
                        "windowId": window_id,
                        "windowLabel": window.get("label") or window_id,
                        "usedPercent": percent,
                    })
                # New period below: fall through to level check with no
                # notified state so a still-high window re-fires once.
            rank = RANK.get(level_of(percent, warn, crit), 0)
            if rank == 0:
                notified.pop(key, None)
                continue
            if rank > RANK.get(notified.get(key), 0):
                level = "crit" if rank == 2 else "warn"
                notified[key] = level
                events.append({
                    "level": level,
                    "providerId": provider_id,
                    "providerName": name,
                    "windowId": window_id,
                    "windowLabel": window.get("label") or window_id,
                    "usedPercent": percent,
                })

    for key in [k for k in notified if k.split("/")[0] in disabled]:
        del notified[key]
    return events, notified


def merge_rate_limited(fresh_providers, prev_providers):
    """Keep last-known windows for providers hit by HTTP 429.

    Returns (merged_providers, limited_ids). A fresh provider whose
    error kind is "rateLimited" is replaced by its previous snapshot
    with stale=True; every other fresh provider is kept as-is.
    """
    prev = {p.get("id"): p for p in (prev_providers or []) if isinstance(p, dict)}
    merged = []
    limited = []
    for provider in fresh_providers or []:
        error = provider.get("error") or {}
        old = prev.get(provider.get("id"))
        if (error.get("kind") == "rateLimited" and isinstance(old, dict)
                and old.get("windows") and not (old.get("error") or {}).get("kind")):
            kept = dict(old)
            kept["stale"] = True
            merged.append(kept)
            limited.append(provider.get("id"))
        else:
            merged.append(provider)
    return merged, limited
