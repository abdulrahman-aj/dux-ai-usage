"""OpenCode Go usage reader (single workspace).

Reads the stored Go API key from opencode.db read-only
(sqlite URI mode=ro: the file is never written) and GETs the
key-authenticated usage endpoint. No refresh flow exists for API-key
auth: on 401/403 the caller is told to reconnect. Nothing is written.
"""

import json
import os
import sqlite3
import urllib.request

BASE_URL = "https://opencode.ai"
USAGE_PATH = "/zen/go/v1/usage"
USER_AGENT = "dux-ai-usage/0.1.0"
TIMEOUT_SECONDS = 15
INTEGRATION_ID = "opencode-go"

WINDOWS = (("rolling", "Rolling 5h"), ("weekly", "Weekly"), ("monthly", "Monthly"))


def db_path():
    data_home = os.environ.get("XDG_DATA_HOME") or os.path.join(
        os.path.expanduser("~"), ".local", "share"
    )
    return os.path.join(data_home, "opencode", "opencode.db")


def _read_api_key(path=None):
    target = path or db_path()
    try:
        connection = sqlite3.connect("file:%s?mode=ro" % target, uri=True, timeout=5)
    except Exception:
        return None
    try:
        rows = connection.execute(
            "SELECT value FROM credential WHERE integration_id = ?", (INTEGRATION_ID,)
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
        if isinstance(percent, bool) or not isinstance(percent, (int, float)):
            continue
        if node.get("status") == "rate-limited":
            percent = 100.0
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
            with urllib.request.urlopen(request, timeout=TIMEOUT_SECONDS) as response:
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
            provider["error"] = {
                "kind": "rateLimited",
                "hint": "Go usage is rate-limited right now. Retrying with last-known values.",
            }
        else:
            provider["error"] = {
                "kind": "unavailable",
                "hint": "Go usage is unreachable right now. Will retry next poll.",
            }
        return provider
    provider["windows"] = parse_usage(payload if isinstance(payload, dict) else {})
    # Go has no banked resets; usage payload carries only windows.
    return provider
