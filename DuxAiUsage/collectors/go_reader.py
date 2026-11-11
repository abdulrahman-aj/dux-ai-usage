"""OpenCode Go usage reader (single workspace).

Reads the stored Go API key from opencode.db read-only
(sqlite URI mode=ro: the file is never written) and GETs the
key-authenticated usage endpoint. No refresh flow exists for API-key
auth: on 401/403 the caller is told to reconnect. Nothing is written.
"""

import json
import os
import pathlib
import sqlite3
import urllib.request
from email.utils import parsedate_to_datetime

BASE_URL = "https://opencode.ai"
USAGE_PATH = "/zen/go/v1/usage"
USAGE_URL = "https://opencode.ai/console/go"
USER_AGENT = "dux-ai-usage/0.1.0"
TIMEOUT_SECONDS = 10
INTEGRATION_ID = "opencode-go"

WINDOWS = (("rolling", "Rolling 5h"), ("weekly", "Weekly"), ("monthly", "Monthly"))


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse redirects: a 3xx here must fail, never carry the key on."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


def _parse_retry_after(headers):
    """Return Retry-After delay in seconds, or None (see claude_reader)."""
    if headers is None:
        return None
    value = None
    getter = getattr(headers, "get", None)
    if callable(getter):
        try:
            value = getter("Retry-After")
        except Exception:
            value = None
        if value is None:
            try:
                value = getter("retry-after")
            except Exception:
                value = None
    if value is None:
        return None
    if not isinstance(value, str):
        value = str(value)
    value = value.strip()
    if not value:
        return None
    if value.isdigit():
        return min(max(int(value), 0), 3600)
    try:
        when = parsedate_to_datetime(value)
    except (TypeError, ValueError, OverflowError):
        return None
    try:
        import datetime as _dt

        now = _dt.datetime.now(_dt.timezone.utc)
        if when.tzinfo is None:
            when = when.replace(tzinfo=_dt.timezone.utc)
        delta = (when - now).total_seconds()
    except Exception:
        return None
    if delta != delta:
        return None
    return min(max(int(delta), 0), 3600)


def db_path():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(data_home, "opencode", "opencode.db")


def _read_api_key(path=None):
    target = path or db_path()
    try:
        uri = pathlib.Path(target).as_uri() + "?mode=ro"
        connection = sqlite3.connect(uri, uri=True, timeout=5)
    except Exception:
        return None
    try:
        rows = connection.execute(
            "SELECT value FROM credential WHERE integration_id = ?"
            " ORDER BY time_updated DESC",
            (INTEGRATION_ID,),
        ).fetchall()
    except Exception:
        return None
    finally:
        try:
            connection.close()
        except Exception:
            pass
    for (value,) in rows:
        try:
            payload = json.loads(value)
        except (TypeError, ValueError):
            continue
        if (
            isinstance(payload, dict)
            and isinstance(payload.get("key"), str)
            and payload["key"]
        ):
            return payload["key"]
    return None


def parse_usage(payload):
    """Normalize a decoded /zen/go/v1/usage payload."""
    windows = []
    usage = payload.get("usage") if isinstance(payload, dict) else None
    if not isinstance(usage, dict):
        return windows
    for window_id, label in WINDOWS:
        node = usage.get(window_id)
        if not isinstance(node, dict):
            continue
        percent = node.get("percent")
        if node.get("status") == "rate-limited":
            # Exhausted window: the server percent may be absent or stale.
            percent = 100.0
        if isinstance(percent, bool) or not isinstance(percent, (int, float)):
            continue
        resets_at = node.get("resetsAt")
        windows.append(
            {
                "id": window_id,
                "label": label,
                "usedPercent": max(0.0, min(100.0, float(percent))),
                "resetsAt": resets_at if isinstance(resets_at, str) else None,
            }
        )
    return windows


def fetch(key=None, opener=None, path=None):
    """Return a normalized OpenCode Go provider dict. Never raises."""
    provider = {
        "id": "opencodeGo",
        "name": "OpenCode Go",
        "plan": "Go",
        "stale": False,
        "windows": [],
        "resets": None,
        "usageUrl": USAGE_URL,
        "error": None,
    }
    api_key = key if isinstance(key, str) and key else _read_api_key(path)
    if not api_key:
        provider["error"] = {
            "kind": "missing",
            "hint": "No OpenCode Go key stored. In opencode run /connect, then wait.",
        }
        return provider
    request = urllib.request.Request(
        BASE_URL + USAGE_PATH,
        method="GET",
        headers={
            "Authorization": "Bearer " + api_key,
            "Accept": "application/json",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        if opener is not None:
            raw = opener(request)
        else:
            with _OPENER.open(request, timeout=TIMEOUT_SECONDS) as response:
                raw = response.read()
        payload = json.loads(raw.decode("utf-8"))
    except Exception as error:  # network/HTTP/JSON: report, never raise
        code = getattr(error, "code", None)
        if code == 401:
            provider["error"] = {
                "kind": "auth",
                "hint": "Go API key was rejected. In opencode run /connect again.",
            }
        elif code == 403:
            provider["error"] = {
                "kind": "auth",
                "hint": "This key has no Go plan. Check the Go console page.",
            }
        elif code == 429:
            hint = "Go usage is rate-limited right now. Will retry next poll."
            retry_after = _parse_retry_after(getattr(error, "headers", None))
            err = {"kind": "rateLimited", "hint": hint}
            if retry_after is not None:
                err["retryAfter"] = retry_after
            provider["error"] = err
        else:
            provider["error"] = {
                "kind": "unavailable",
                "hint": "Go usage is unreachable right now. Will retry next poll.",
            }
        return provider
    provider["windows"] = parse_usage(payload if isinstance(payload, dict) else {})
    # Go has no banked resets; usage payload carries only windows.
    return provider
