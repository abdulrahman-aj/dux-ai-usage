"""Claude (Claude Code subscription) usage reader.

Read-only GET on the same endpoint Claude Code's /usage view uses, with
the CLI-owned OAuth access token. The CLI owns refresh: on 401 the caller
is told to run any Claude Code command and retry. Nothing is written.
"""

import json
import os
import urllib.request

API_URL = "https://api.anthropic.com/api/oauth/usage"
BETA_HEADER = "oauth-2025-04-20"
USER_AGENT = "dux-ai-usage/0.1.0"
TIMEOUT_SECONDS = 15

CREDENTIALS_PATH = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")
USAGE_URL = "https://claude.ai/settings/usage"


def _read_credentials(path=CREDENTIALS_PATH):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    except (OSError, ValueError):
        return {}
    if not isinstance(payload, dict):
        return {}
    oauth = payload.get("claudeAiOauth")
    return oauth if isinstance(oauth, dict) else {}


def _read_access_token(path=CREDENTIALS_PATH):
    token = _read_credentials(path).get("accessToken")
    return token if isinstance(token, str) and token else None


def _read_plan(path=CREDENTIALS_PATH):
    sub = _read_credentials(path).get("subscriptionType")
    return sub.strip().capitalize() if isinstance(sub, str) and sub.strip() else ""


def _window(window_id, label, node):
    percent = node.get("utilization") if isinstance(node, dict) else None
    if isinstance(percent, bool) or not isinstance(percent, (int, float)):
        percent = None
    resets_at = node.get("resets_at") if isinstance(node, dict) else None
    return {
        "id": window_id,
        "label": label,
        "usedPercent": float(percent) if percent is not None else None,
        "resetsAt": resets_at if isinstance(resets_at, str) else None,
    }


def parse_usage(payload):
    """Normalize a decoded /api/oauth/usage payload (tolerant of nulls)."""
    windows = []
    if isinstance(payload, dict):
        windows.append(_window("fiveHour", "5-hour", payload.get("five_hour")))
        windows.append(_window("weekly", "Weekly", payload.get("seven_day")))
        for entry in payload.get("limits") or []:
            if not isinstance(entry, dict):
                continue
            if entry.get("kind") != "weekly_scoped":
                continue
            scope = entry.get("scope") or {}
            model = scope.get("model") or {}
            display = model.get("display_name")
            if not isinstance(display, str) or not display:
                continue
            percent = entry.get("percent")
            if isinstance(percent, bool) or not isinstance(percent, (int, float)):
                continue
            windows.append(
                {
                    "id": "weekly-"
                    + "".join(c.lower() if c.isalnum() else "-" for c in display).strip(
                        "-"
                    ),
                    "label": "Weekly · " + display,
                    "usedPercent": float(percent),
                    "resetsAt": (
                        entry.get("resets_at")
                        if isinstance(entry.get("resets_at"), str)
                        else None
                    ),
                }
            )
    plan = ""
    if isinstance(payload, dict):
        sub = payload.get("subscriptionType")
        if isinstance(sub, str) and sub.strip():
            plan = sub.strip().capitalize()
    return {"plan": plan, "windows": windows}


def fetch(token=None, opener=None, credentials_path=CREDENTIALS_PATH):
    """Return a normalized Claude provider dict. Never raises."""
    provider = {
        "id": "claude",
        "name": "Claude",
        "plan": "",
        "stale": False,
        "windows": [],
        "resets": None,
        "error": None,
    }
    access_token = (
        token
        if isinstance(token, str) and token
        else _read_access_token(credentials_path)
    )
    if not access_token:
        provider["error"] = {
            "kind": "missing",
            "hint": "Claude Code isn't signed in here. Sign in, then wait for the next poll.",
        }
        return provider
    request = urllib.request.Request(
        API_URL,
        method="GET",
        headers={
            "Authorization": "Bearer " + access_token,
            "anthropic-beta": BETA_HEADER,
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
                "hint": "Claude sign-in expired. Run any Claude Code command to refresh, then wait.",
            }
        elif code == 429:
            provider["error"] = {
                "kind": "rateLimited",
                "hint": "Claude usage is rate-limited right now. Retrying with last-known values.",
            }
        else:
            provider["error"] = {
                "kind": "unavailable",
                "hint": "Claude usage is unreachable right now. Will retry next poll.",
            }
        return provider
    parsed = parse_usage(payload if isinstance(payload, dict) else {})
    provider["plan"] = parsed["plan"] or _read_plan(credentials_path)
    provider["windows"] = parsed["windows"]
    # The usage payload exposes no banked-reset count, so no resets row.
    return provider
