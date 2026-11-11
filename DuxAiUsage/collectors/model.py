"""Normalized usage document and threshold-crossing events.

Pure functions over plain data so behavior is unit-testable. The QML
daemon shells out to collect.py (which uses this module) instead of
reimplementing the rules, keeping a single implementation.

Document shape emitted by collect.py::

    {"fetchedAt": str, "providers": [provider...],
     "events": [event...], "notified": {key: level}, "limited": [providerId...]}

provider::

    {"id": str, "name": str, "plan": str, "stale": bool,
     "staleSince": str | None, "updatedAt": str | None,
     "retryAfterSec": int | None,
     "headlineId": str | None, "headlineShort": bool, "usageUrl": str | None,
     "windows": [{"id": str, "label": str,
                  "usedPercent": float | None, "resetsAt": str | None}],
     "resets": {"available": int, "url": str} | None,
     "error": {"kind": str, "hint": str, "retryAfter": int | None} | None}

headlineId names the window the pill and cards headline (see
headline_window); headlineShort marks a short window taking over the
long default, so surfaces can show the tiny window mark without
reimplementing the rule. staleSince is the fetch the last-known values came
from, so the stale tag shows only for kept values, with its age.
updatedAt is the provider's own last successful fetch (ISO): surfaces
show each card's own "Updated ... ago" from it instead of one global
stamp, so a rate-limited Claude reads stale-but-dated while Codex
stays fresh. retryAfterSec carries the server's Retry-After hint
(seconds) for the daemon's backoff. usageUrl is the provider usage
page behind the quiet open link.

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
    weekly so a future window kind cannot hijack the pill.
    """
    if isinstance(window_id, str):
        return _WINDOW_RANK.get(window_id, 1)
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


def seed_notified(curr_providers, warn, crit):
    """Notified map for everything currently true, emitting no events.

    Why: the daemon passes this on its first poll after startup so a
    window that was already exhausted while the shell was off records
    its level silently instead of re-alerting.
    """
    warn, crit = clamp_thresholds(warn, crit)
    seeded = {}
    for provider in curr_providers or []:
        provider_id = provider.get("id") if isinstance(provider, dict) else None
        windows = provider.get("windows") if isinstance(provider, dict) else None
        for window in windows or []:
            if not isinstance(window, dict) or not window.get("id"):
                continue
            percent = window.get("usedPercent")
            if isinstance(percent, bool) or not isinstance(percent, (int, float)):
                continue
            level = level_of(float(percent), warn, crit)
            if level in ("warn", "crit"):
                seeded[provider_id + "/" + window["id"]] = level
    return seeded


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


def compute_events(curr_providers, notified, warn, crit, reset_notify=True):
    """Compare snapshots, returning (events, new_notified).

    Rules: an event fires once per window per upward crossing
    (ok->warn, warn->crit, ok->crit). Dropping below warn re-arms the
    window; a window last seen at crit emits a "reset" event then (when
    reset_notify is on). resetsAt is deliberately ignored: rolling
    windows move it every poll, which used to re-fire warnings.
    Windows that vanish (and providers that poll clean) lose their
    notified state, so reappearing windows refire like a re-arm.
    """
    warn, crit = clamp_thresholds(warn, crit)
    curr = _window_map(curr_providers)
    notified = dict(notified or {})
    events = []

    for provider_id, windows in curr.items():
        name = _provider_name(curr_providers, provider_id)
        for window_id, window in windows.items():
            key = provider_id + "/" + window_id
            percent = window.get("usedPercent")
            if isinstance(percent, bool) or not isinstance(percent, (int, float)):
                continue
            percent = float(percent)
            rank = RANK.get(level_of(percent, warn, crit), 0)
            if rank == 0:
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

    # Forget windows that no longer exist (e.g. a scoped row filtered
    # out at 0%): a reappearing window refires by level, like a re-arm.
    # Providers in a failed poll keep their state: the error carries no
    # windows, which must not count as "vanished".
    errored = {
        provider.get("id")
        for provider in (curr_providers or [])
        if isinstance(provider, dict) and isinstance(provider.get("error"), dict)
    }
    current_keys = {
        provider_id + "/" + window_id
        for provider_id, windows in curr.items()
        for window_id in windows
    }
    for key in [
        k for k in notified if k not in current_keys and k.split("/")[0] not in errored
    ]:
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


# Claude shares one OAuth token with every running Claude Code session,
# so the plugin stays extra gentle there while Codex/Go keep the user's
# poll interval: a Claude fetch within this window is reused, not refetched.
CLAUDE_MIN_SECONDS = 600


def _parse_iso(value):
    """Parse an ISO-8601 stamp to an aware datetime, or None."""
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip()
    if text.endswith("Z"):
        text = text[:-1] + "+00:00"
    try:
        import datetime as _dt

        moment = _dt.datetime.fromisoformat(text)
    except (TypeError, ValueError):
        return None
    if moment.tzinfo is None:
        try:
            import datetime as _dt

            moment = moment.replace(tzinfo=_dt.timezone.utc)
        except Exception:
            return None
    return moment


def claude_due(updated_at_iso, now_iso, min_seconds=CLAUDE_MIN_SECONDS):
    """True when Claude is due for a refetch (testable scheduling rule).

    Why here, not QML: the skip decision gates a network call, so it
    needs unit tests. Due when either stamp is missing/invalid or the
    last good fetch is at least min_seconds old.
    """
    try:
        window = float(min_seconds)
    except (TypeError, ValueError):
        window = float(CLAUDE_MIN_SECONDS)
    updated = _parse_iso(updated_at_iso)
    now = _parse_iso(now_iso)
    if updated is None or now is None:
        return True
    return (now - updated).total_seconds() >= window


def next_backoff(limited, prev_backoff, poll_minutes, retry_after_sec=None):
    """Next backoff in minutes after a poll (testable backoff rule).

    Exponential doubling (capped at 30) on rate-limited polls, but never
    below the server's Retry-After hint when one was served. No limit
    (and no hint) resets to the normal schedule.
    """
    if not limited and retry_after_sec is None:
        return 0
    try:
        base = float(poll_minutes)
    except (TypeError, ValueError):
        base = 5.0
    if not base or base < 1:
        base = 5.0
    try:
        prev = float(prev_backoff or 0)
    except (TypeError, ValueError):
        prev = 0
    need = 0
    if retry_after_sec is not None:
        try:
            need = int(-(-float(retry_after_sec) // 60))
        except (TypeError, ValueError):
            need = 0
        need = max(need, 0)
    if not limited:
        return min(need, 30) if need else 0
    grown = int(prev or base) * 2 if prev else int(base) * 2
    return min(max(grown, need, 1), 30)


def _retry_after_of(error):
    try:
        value = (error or {}).get("retryAfter")
    except AttributeError:
        return None
    try:
        seconds = int(value)
    except (TypeError, ValueError):
        return None
    return seconds if seconds >= 0 else None


def merge_rate_limited(
    fresh_providers, prev_providers, prev_fetched_at=None, now_iso=None
):
    """Keep last-known windows for rate-limited or unreachable providers.

    Returns (merged_providers, limited_ids). A fresh provider whose
    error kind is "rateLimited" or "unavailable" is replaced by its
    previous snapshot with stale=True (keeping the original staleSince
    fetch time and the provider's own updatedAt so surfaces can say how
    old the values are); every other fresh provider is kept as-is with
    any stale marker cleared and updatedAt stamped to now_iso.
    limited_ids (which the daemon backs off for) holds every
    rate-limited provider, reused or first-seen: unreachable ones retry
    on the normal schedule. kept/fresh rate-limited providers carry
    rateLimited=True plus retryAfterSec (the server's Retry-After hint,
    when served) for the backoff; other merges clear both.
    """
    prev = {p.get("id"): p for p in (prev_providers or []) if isinstance(p, dict)}
    merged = []
    limited = []
    for provider in fresh_providers or []:
        error = provider.get("error") or {}
        old = prev.get(provider.get("id"))
        kind = error.get("kind")
        is_limited = kind == "rateLimited"
        retry_after = _retry_after_of(error)
        if is_limited:
            limited.append(provider.get("id"))
        if (
            kind in ("rateLimited", "unavailable")
            and isinstance(old, dict)
            and old.get("windows")
            and not (old.get("error") or {}).get("kind")
        ):
            kept = dict(old)
            kept["stale"] = True
            kept["staleSince"] = old.get("staleSince") or prev_fetched_at
            kept["updatedAt"] = (
                old.get("updatedAt") or old.get("staleSince") or prev_fetched_at
            )
            if is_limited:
                kept["rateLimited"] = True
            else:
                kept.pop("rateLimited", None)
            if retry_after is not None:
                kept["retryAfterSec"] = retry_after
            else:
                kept.pop("retryAfterSec", None)
            kept.pop("retryInMinutes", None)
            merged.append(kept)
        else:
            if is_limited:
                provider["rateLimited"] = True
            else:
                provider.pop("rateLimited", None)
            if retry_after is not None:
                provider["retryAfterSec"] = retry_after
            else:
                provider.pop("retryAfterSec", None)
            provider.pop("retryInMinutes", None)
            if not isinstance(provider.get("error"), dict):
                provider["stale"] = False
                provider.pop("staleSince", None)
                if now_iso is not None:
                    provider["updatedAt"] = now_iso
                else:
                    provider.pop("updatedAt", None)
            merged.append(provider)
    return merged, limited
