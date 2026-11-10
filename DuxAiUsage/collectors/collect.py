#!/usr/bin/env python3
"""Poll Claude, Codex and OpenCode Go and print one normalized JSON document.

Read-only against every account: credential files and opencode.db are
opened read-only, tokens are never refreshed or printed, and failures
become per-provider error hints instead of tracebacks.

Usage:
    collect.py [--prev '<snapshot json>'] [--notified '<json>']
               [--warn PCT] [--crit PCT] [--disable id,...]
               [--no-reset-notify]
"""

import argparse
import datetime as dt
import json
import os
import sys
from concurrent.futures import ThreadPoolExecutor

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import claude_reader
import codex_reader
import go_reader
from model import (
    LONG_WINDOW,
    clamp_thresholds,
    compute_events,
    headline_window,
    merge_rate_limited,
    visible_windows,
)

READERS = (
    ("claude", claude_reader.fetch),
    ("codex", codex_reader.fetch),
    ("opencodeGo", go_reader.fetch),
)


def _parse_json_arg(value, default):
    if not value:
        return default
    try:
        parsed = json.loads(value)
    except ValueError:
        return default
    return parsed if isinstance(parsed, dict) else default


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--prev",
        default="",
        help="previous {'providers': [...]} snapshot for 429 reuse",
    )
    parser.add_argument(
        "--notified", default="", help="previous {windowKey: level} notified map"
    )
    parser.add_argument("--warn", type=float, default=80.0)
    parser.add_argument("--crit", type=float, default=100.0)
    parser.add_argument(
        "--disable", default="", help="comma-separated provider ids to skip"
    )
    parser.add_argument("--no-reset-notify", action="store_true")
    args = parser.parse_args(argv)

    warn, crit = clamp_thresholds(args.warn, args.crit)
    disabled = {p.strip() for p in args.disable.split(",") if p.strip()}
    prev = _parse_json_arg(args.prev, {})
    prev_providers = prev.get("providers")
    prev_fetched = prev.get("fetchedAt")
    notified = _parse_json_arg(args.notified, {})

    # Readers run concurrently (each ~10 s max) so one slow provider
    # cannot eat the shell's whole poll timeout; order stays READERS order.
    wanted = [reader for provider_id, reader in READERS if provider_id not in disabled]
    with ThreadPoolExecutor(max_workers=len(READERS)) as pool:
        fresh = list(pool.map(lambda reader: reader(), wanted))

    merged, limited = merge_rate_limited(fresh, prev_providers, prev_fetched)
    for provider in merged:
        # Hide unused per-model rows here so every surface (and test)
        # shares one rule; annotate the pill/cards headline window.
        provider["windows"] = visible_windows(provider)
        headline = headline_window(provider, warn, crit)
        provider["headlineId"] = headline.get("id") if headline else None
        provider["headlineShort"] = bool(headline) and headline.get(
            "id"
        ) != LONG_WINDOW.get(provider.get("id"))
    events, new_notified = compute_events(
        merged,
        notified,
        warn,
        crit,
        reset_notify=not args.no_reset_notify,
    )

    document = {
        "fetchedAt": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
        "providers": merged,
        "events": events,
        "notified": new_notified,
        "limited": limited,
    }
    print(json.dumps(document, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
