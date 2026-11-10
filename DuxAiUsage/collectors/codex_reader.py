"""Codex (ChatGPT plan) usage reader.

Spawns `codex app-server` (stdio JSON-RPC) and calls the read-only
`account/rateLimits/read` method — the same data as the TUI /status
view. Codex owns authentication and refresh; this script never touches
auth files. Windows are classified by windowDurationMins, never by
slot: weekly-only plans return the weekly window as primary with
secondary null.
"""

import datetime as dt
import json
import os
import select
import shutil
import subprocess

USER_AGENT = "dux-ai-usage/0.1.0"
RPC_TIMEOUT_SECONDS = 20
USAGE_URL = "https://chatgpt.com/codex/settings/usage"

# windowDurationMins -> (window id, label)
DURATIONS = {
    300: ("fiveHour", "5-hour"),
    10080: ("weekly", "Weekly"),
    43200: ("monthly", "Monthly"),
}


def runtime_env():
    home = os.path.expanduser("~")
    parts = [
        os.environ.get("PATH", ""),
        os.path.join(home, ".local", "bin"),
        os.path.join(home, ".local", "share", "mise", "shims"),
    ]
    env = os.environ.copy()
    env["PATH"] = os.pathsep.join(part for part in parts if part)
    return env


def _rpc(proc, request_id, method, params=None):
    proc.stdin.write(
        json.dumps({"id": request_id, "method": method, "params": params or {}}) + "\n"
    )
    proc.stdin.flush()
    deadline = dt.datetime.now().timestamp() + RPC_TIMEOUT_SECONDS
    while dt.datetime.now().timestamp() < deadline:
        ready, _, _ = select.select([proc.stdout], [], [], 0.25)
        if not ready:
            continue
        line = proc.stdout.readline()
        if not line:
            break
        try:
            message = json.loads(line)
        except ValueError:
            continue
        if message.get("id") == request_id:
            return message
    raise TimeoutError(method)


def iso_from_epoch(value):
    try:
        moment = dt.datetime.fromtimestamp(int(value), dt.timezone.utc)
    except (TypeError, ValueError, OverflowError, OSError):
        return None
    return moment.isoformat(timespec="seconds").replace("+00:00", "Z")


def _duration_label(mins):
    if mins % 1440 == 0:
        return "%dd" % (mins // 1440)
    if mins % 60 == 0:
        return "%dh" % (mins // 60)
    return "%dm" % mins


def classify_window(node):
    """Map one primary/secondary style window node to a normalized window."""
    if not isinstance(node, dict):
        return None
    percent = node.get("usedPercent")
    if isinstance(percent, bool) or not isinstance(percent, (int, float)):
        return None
    try:
        mins = int(node.get("windowDurationMins"))
    except (TypeError, ValueError):
        return None
    window_id, label = DURATIONS.get(mins, ("w%d" % mins, _duration_label(mins)))
    return {
        "id": window_id,
        "label": label,
        "usedPercent": max(0.0, min(100.0, float(percent))),
        "resetsAt": iso_from_epoch(node.get("resetsAt")),
        "_mins": mins,
    }


def _pick_limits(result):
    """Choose the single-workspace limits object.

    Prefer the 'codex' entry of rateLimitsByLimitId (the map exists for
    future multi-pool shapes), else the top-level rateLimits, else the
    first map entry.
    """
    if not isinstance(result, dict):
        return {}
    by_id = result.get("rateLimitsByLimitId")
    if isinstance(by_id, dict) and by_id:
        if isinstance(by_id.get("codex"), dict):
            return by_id["codex"]
        for value in by_id.values():
            if isinstance(value, dict):
                return value
    limits = result.get("rateLimits")
    return limits if isinstance(limits, dict) else {}


def parse_result(result):
    """Normalize an account/rateLimits/read result dict."""
    limits = _pick_limits(result)
    windows = []
    for node in (limits.get("primary"), limits.get("secondary")):
        window = classify_window(node)
        if window is not None:
            window.pop("_mins", None)
            windows.append(window)
    # Keep a stable order: 5-hour, weekly, monthly, then anything else.
    order = {"fiveHour": 0, "weekly": 1, "monthly": 2}
    windows.sort(key=lambda w: (order.get(w["id"], 99), w["id"]))
    plan = ""
    plan_type = limits.get("planType")
    if isinstance(plan_type, str) and plan_type.strip():
        plan = "Codex " + plan_type.strip().capitalize()
    resets = None
    credits = result.get("rateLimitResetCredits")
    if isinstance(credits, dict) and isinstance(credits.get("availableCount"), int):
        resets = {"available": max(0, credits["availableCount"]), "url": USAGE_URL}
    return {"plan": plan, "windows": windows, "resets": resets}


def fetch_limits(run=None):
    """Return the raw result dict of account/rateLimits/read."""
    if run is not None:
        return run()
    codex = shutil.which("codex", path=runtime_env()["PATH"])
    if not codex:
        raise FileNotFoundError("codex not found in PATH")
    proc = subprocess.Popen(
        [codex, "-s", "read-only", "-a", "never", "app-server"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        env=runtime_env(),
    )
    try:
        _rpc(
            proc,
            1,
            "initialize",
            {"clientInfo": {"name": "dux-ai-usage", "version": "1"}},
        )
        proc.stdin.write(json.dumps({"method": "initialized", "params": {}}) + "\n")
        proc.stdin.flush()
        response = _rpc(proc, 2, "account/rateLimits/read")
    finally:
        try:
            proc.terminate()
            proc.wait(timeout=2)
        except Exception:
            try:
                proc.kill()
            except Exception:
                pass
    result = (response.get("result") or {}) if isinstance(response, dict) else {}
    if not isinstance(result, dict):
        return {}
    return result


def fetch(run=None):
    """Return a normalized Codex provider dict. Never raises."""
    provider = {
        "id": "codex",
        "name": "Codex",
        "plan": "",
        "stale": False,
        "windows": [],
        "resets": None,
        "error": None,
    }
    try:
        result = fetch_limits(run=run)
    except FileNotFoundError:
        provider["error"] = {
            "kind": "missing",
            "hint": "Codex CLI isn't installed. Install it, then wait for the next poll.",
        }
        return provider
    except Exception:
        provider["error"] = {
            "kind": "unavailable",
            "hint": "Codex quota is unreachable right now. Will retry next poll.",
        }
        return provider
    if not result:
        provider["error"] = {
            "kind": "auth",
            "hint": "Codex isn't signed in. Run `codex login`, then wait for the next poll.",
        }
        return provider
    parsed = parse_result(result)
    if not parsed["windows"]:
        provider["error"] = {
            "kind": "auth",
            "hint": "Codex isn't signed in. Run `codex login`, then wait for the next poll.",
        }
        return provider
    provider["plan"] = parsed["plan"]
    provider["windows"] = parsed["windows"]
    provider["resets"] = parsed["resets"]
    return provider
