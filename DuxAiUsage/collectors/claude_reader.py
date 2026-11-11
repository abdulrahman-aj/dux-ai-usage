"""Claude (Claude Code subscription) usage reader.

Read-only GET on the same endpoint Claude Code's /usage view uses, with
the CLI-owned OAuth access token. The CLI owns refresh: on 401 the caller
is told to run any Claude Code command and retry. Nothing is written.
"""

import json
import os
import urllib.request

API_URL = "https://api.anthropic.com/api/oauth/usage"
# Read-only status query: same GET endpoint, asks the server to include
# the reset-status blocks (cedar_ember grants + juniper_tide weekly
# reset) that Claude Code's /usage view uses. No mutation, no extra
# endpoint; windows keys are identical with or without it.
STATUS_QUERY = "?at_wall=1&skip_spend=1"
BETA_HEADER = "oauth-2025-04-20"
USER_AGENT = "dux-ai-usage/0.1.0"
TIMEOUT_SECONDS = 10
USAGE_URL = "https://claude.ai/settings/usage"

CREDENTIALS_PATH = os.path.join(os.path.expanduser("~"), ".claude", ".credentials.json")


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse redirects: a 3xx here must fail, never carry the token on."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


_OPENER = urllib.request.build_opener(_NoRedirect)


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


def _window(window_id, label, node):
    percent = node.get("utilization") if isinstance(node, dict) else None
    if isinstance(percent, bool) or not isinstance(percent, (int, float)):
        percent = None
    resets_at = node.get("resets_at") if isinstance(node, dict) else None
    return {
        "id": window_id,
        "label": label,
        "usedPercent": max(0.0, min(100.0, float(percent)))
        if percent is not None
        else None,
        "resetsAt": resets_at if isinstance(resets_at, str) else None,
    }


def parse_usage(payload):
    """Normalize a decoded /api/oauth/usage payload to windows (tolerant of nulls)."""
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
                    "usedPercent": max(0.0, min(100.0, float(percent))),
                    "resetsAt": (
                        entry.get("resets_at")
                        if isinstance(entry.get("resets_at"), str)
                        else None
                    ),
                }
            )
    return windows


def _resets_left(grant):
    value = grant.get("resets_left")
    if isinstance(value, bool):
        return 0
    if isinstance(value, int) and value > 0:
        return value
    if isinstance(value, float) and value > 0:
        return int(value)
    return 0


def _grant_usable(grant):
    if grant.get("paused") is True or grant.get("usable_now") is False:
        return False
    return True


def parse_resets(payload):
    """Count banked Claude resets from the read-only status blocks.

    cedar_ember.grants holds per-grant resets_left (e.g. a Fable grant);
    juniper_tide.available marks the weekly full reset. Returns None when
    nothing is banked so the row stays quiet, else {"available", "url",
    "label"?, "resetsAt"?}. Tolerant of missing blocks/keys.
    """
    if not isinstance(payload, dict):
        return None
    cedar = payload.get("cedar_ember")
    juniper = payload.get("juniper_tide")
    grants = []
    if isinstance(cedar, dict) and isinstance(cedar.get("grants"), list):
        for entry in cedar["grants"]:
            if not isinstance(entry, dict):
                continue
            left = _resets_left(entry)
            if left > 0 and _grant_usable(entry):
                grants.append((entry, left))
    juniper_available = isinstance(juniper, dict) and juniper.get("available") is True
    total = sum(left for _, left in grants) + (1 if juniper_available else 0)
    if total <= 0:
        return None
    labels = []
    for entry, _ in grants:
        label = entry.get("label")
        if isinstance(label, str) and label.strip() and label not in labels:
            labels.append(label.strip())
    if juniper_available and "weekly reset" not in [s.lower() for s in labels]:
        labels.append("weekly reset")
    resets_at = None
    for entry, _ in grants:
        for key in ("ends_at", "expires_at"):
            value = entry.get(key)
            if isinstance(value, str) and value:
                resets_at = value
                break
        if resets_at:
            break
    if resets_at is None and isinstance(juniper, dict):
        for key in ("next_available_at", "weekly_resets_at"):
            value = juniper.get(key)
            if isinstance(value, str) and value:
                resets_at = value
                break
    if resets_at is None and isinstance(cedar, dict):
        value = cedar.get("weekly_resets_at")
        if isinstance(value, str) and value:
            resets_at = value
    out = {"available": total, "url": USAGE_URL}
    if labels:
        out["label"] = ", ".join(labels)
    if resets_at:
        out["resetsAt"] = resets_at
    return out


def fetch(token=None, opener=None, credentials_path=CREDENTIALS_PATH):
    """Return a normalized Claude provider dict. Never raises."""
    provider = {
        "id": "claude",
        "name": "Claude",
        "plan": "",
        "stale": False,
        "windows": [],
        "resets": None,
        "usageUrl": USAGE_URL,
        "error": None,
    }
    creds = _read_credentials(credentials_path)
    access_token = (
        token if isinstance(token, str) and token else creds.get("accessToken")
    )
    if not isinstance(access_token, str) or not access_token:
        provider["error"] = {
            "kind": "missing",
            "hint": "Claude Code isn't signed in here. Sign in, then wait for the next poll.",
        }
        return provider
    request = urllib.request.Request(
        API_URL + STATUS_QUERY,
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
            with _OPENER.open(request, timeout=TIMEOUT_SECONDS) as response:
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
                "hint": "Claude usage is rate-limited right now. Will retry next poll.",
            }
        else:
            provider["error"] = {
                "kind": "unavailable",
                "hint": "Claude usage is unreachable right now. Will retry next poll.",
            }
        return provider
    # The plan comes from the credentials file, never the usage payload.
    sub = creds.get("subscriptionType")
    provider["plan"] = (
        sub.strip().capitalize() if isinstance(sub, str) and sub.strip() else ""
    )
    provider["windows"] = parse_usage(payload if isinstance(payload, dict) else {})
    provider["resets"] = parse_resets(payload if isinstance(payload, dict) else {})
    return provider
