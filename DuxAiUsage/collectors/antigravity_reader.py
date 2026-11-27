"""Antigravity (Google AI Pro/Ultra plan) usage reader.

Runs the Antigravity CLI's read-only slash command `agy -p /usage
--output-format json`, the same data as the TUI /usage panel. agy owns
sign-in and token refresh (keyring); this script never touches its
credentials. Why not call the Code Assist quota API directly: it gates
on the client identity, and only agy is a sanctioned client.

Each model group ("Gemini Models", "Claude and GPT models") has its
own 5-hour and weekly bucket, so window ids are "<pool>.<kind>"
(e.g. "gemini.weekly"); model.window_kind() strips the pool for the
headline rule.
"""

import json
import shutil
import subprocess

from codex_reader import runtime_env

TIMEOUT_SECONDS = 10
# Antigravity settings, opened at the Models screen (plan + model
# quota live here; the CLI /usage panel stays the canonical numbers).
USAGE_URL = (
    "https://antigravity.google.com/remote?settingsOpen=true&settingsScreen=Models"
)

# bucket "window" -> (window kind, label)
KINDS = {"5h": ("fiveHour", "5-hour"), "weekly": ("weekly", "Weekly")}


class AuthError(Exception):
    """agy has no usable Google sign-in (or only an API key)."""


def _pool(group_name, bucket_id):
    """Short pool key and label for a model group.

    The key comes from the bucket id prefix ("gemini-5h" -> "gemini",
    "3p-weekly" -> "3p") so it stays stable if Google renames the
    group; the label is the group name minus its " models" suffix.
    """
    key = bucket_id.rsplit("-", 1)[0] if "-" in bucket_id else bucket_id
    label = group_name.strip()
    if label.lower().endswith(" models"):
        label = label[: -len(" models")]
    return key or label.lower(), label or key


def parse_usage(document):
    """Normalize the `agy -p /usage --output-format json` document."""
    command = document.get("command") if isinstance(document, dict) else None
    data = command.get("data") if isinstance(command, dict) else None
    groups = data.get("groups") if isinstance(data, dict) else None
    windows = []
    for group in groups if isinstance(groups, list) else []:
        if not isinstance(group, dict):
            continue
        pool_windows = []
        for bucket in group.get("buckets") or []:
            if not isinstance(bucket, dict):
                continue
            if bucket.get("disabled") is True:
                # Weekly exhausted: agy marks the pool's 5-hour bucket
                # disabled ("does not currently apply") instead of
                # omitting it; showing it at 100% would fake a 5-hour
                # burnout and steal the pill headline.
                continue
            kind = KINDS.get(bucket.get("window"))
            remaining = bucket.get("remaining_fraction")
            bucket_id = bucket.get("id")
            if (
                kind is None
                or isinstance(remaining, bool)
                or not isinstance(remaining, (int, float))
                or not isinstance(bucket_id, str)
            ):
                continue
            key, label = _pool(str(group.get("name") or ""), bucket_id)
            reset = bucket.get("reset_time")
            pool_windows.append(
                {
                    "id": key + "." + kind[0],
                    "label": kind[1] + " · " + label,
                    "usedPercent": max(0.0, min(100.0, (1.0 - remaining) * 100.0)),
                    "resetsAt": reset if isinstance(reset, str) and reset else None,
                    # The pill and alerts follow the Gemini pool: the
                    # third-party pool is a tiny shared allowance that is
                    # exhausted almost immediately, so letting it headline
                    # would pin the pill at 100% over quota nobody uses.
                    # Its rows stay visible in the card as detail.
                    "headline": key == "gemini",
                }
            )
        # agy lists weekly first; show 5-hour first like the others.
        pool_windows.sort(key=lambda w: w["id"].endswith(".weekly"))
        windows.extend(pool_windows)
    return windows


def run_usage():
    """Return (exit code, stdout) of agy's /usage print-mode command."""
    env = runtime_env()
    agy = shutil.which("agy", path=env["PATH"])
    if not agy:
        raise FileNotFoundError("agy not found in PATH")
    # A passive probe must never self-update agy or pop a browser: when
    # signed out, print mode starts an OAuth flow that opens $BROWSER.
    env["AGY_CLI_DISABLE_AUTO_UPDATE"] = "true"
    env["BROWSER"] = "true"
    try:
        done = subprocess.run(
            [agy, "-p", "/usage", "--output-format", "json"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
            env=env,
        )
    except subprocess.TimeoutExpired as error:
        # Signed out, agy waits 60 s for an OAuth code; say so instead
        # of reporting a generic timeout.
        # TimeoutExpired carries bytes even with text=True.
        output = "".join(
            part.decode("utf-8", "replace") if isinstance(part, bytes) else part
            for part in (error.stdout, error.stderr)
            if part
        )
        if "Authentication required" in output:
            raise AuthError("agy is signed out")
        raise
    return done.returncode, done.stdout


def fetch(run=None):
    """Return a normalized Antigravity provider dict. Never raises.

    The optional run hook (tests) returns (exit code, stdout) like
    run_usage, or raises like it.
    """
    provider = {
        "id": "antigravity",
        "name": "Antigravity",
        "plan": "",
        "stale": False,
        "windows": [],
        "resets": None,
        "usageUrl": USAGE_URL,
        "error": None,
    }
    try:
        code, stdout = (run or run_usage)()
        if code == 2:
            # agy exits 2 when it runs on a GEMINI_API_KEY: no plan quota.
            raise AuthError("api key")
        if code != 0:
            raise RuntimeError("agy exited %s" % code)
        document = json.loads(stdout)
    except FileNotFoundError:
        provider["error"] = {
            "kind": "missing",
            "hint": "Antigravity CLI (agy) isn't installed. Install it, then wait.",
        }
        return provider
    except AuthError:
        provider["error"] = {
            "kind": "auth",
            "hint": "agy isn't signed in to your Google plan. Run `agy` once to sign in.",
        }
        return provider
    except Exception:
        provider["error"] = {
            "kind": "unavailable",
            "hint": "Antigravity quota is unreachable right now. Will retry next poll.",
        }
        return provider
    windows = parse_usage(document)
    if not windows:
        provider["error"] = {
            "kind": "unavailable",
            "hint": "Antigravity returned no quota windows. Will retry next poll.",
        }
        return provider
    provider["windows"] = windows
    return provider
