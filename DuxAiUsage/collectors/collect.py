#!/usr/bin/env python3
"""Poll Claude, Codex and OpenCode Go and print one normalized JSON document.

Read-only against every account: credential files and opencode.db are
opened read-only, tokens are never refreshed or printed, and failures
become per-provider error hints instead of tracebacks.

Usage:
    collect.py [--prev '<snapshot json>'] [--notified '<json>']
               [--warn PCT] [--crit PCT] [--disable id,...]
               [--claude-min-minutes MIN] [--now ISO]
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
    CLAUDE_MIN_SECONDS,
    LONG_WINDOW,
    clamp_thresholds,
    claude_due,
    compute_events,
    headline_window,
    merge_rate_limited,
    seed_notified,
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
    parser.add_argument(
        "--seed",
        action="store_true",
        help="startup first poll: record current levels silently, emit no events",
    )
    parser.add_argument(
        "--claude-min-minutes",
        type=float,
        default=CLAUDE_MIN_SECONDS / 60.0,
        help="minimum age of the last good Claude fetch before refetching",
    )
    parser.add_argument(
        "--now",
        default="",
        help="current time ISO-8601 (tests only; defaults to now)",
    )
    args = parser.parse_args(argv)

    warn, crit = clamp_thresholds(args.warn, args.crit)
    try:
        claude_min_seconds = float(args.claude_min_minutes) * 60.0
    except (TypeError, ValueError):
        claude_min_seconds = float(CLAUDE_MIN_SECONDS)
    if claude_min_seconds < 0:
        claude_min_seconds = 0.0
    now_iso = args.now.strip() or dt.datetime.now(dt.timezone.utc).isoformat(
        timespec="seconds"
    )
    disabled = {p.strip() for p in args.disable.split(",") if p.strip()}
    prev = _parse_json_arg(args.prev, {})
    prev_providers = prev.get("providers")
    prev_by_id = {
        p.get("id"): p
        for p in (prev_providers or [])
        if isinstance(p, dict) and p.get("id")
    }
    prev_fetched = prev.get("fetchedAt")
    notified = _parse_json_arg(args.notified, {})

    # Claude shares its token with every running Claude Code session, so
    # refetching it on every poll burns the shared 429 budget for slowly
    # moving windows (5-hour/weekly). Reuse a recent good Claude fetch
    # instead; Codex/Go still poll on the normal schedule. Manual refresh
    # gets the same per-provider debounce for free.
    skip_ids = set()
    prev_claude = prev_by_id.get("claude")
    if (
        "claude" not in disabled
        and isinstance(prev_claude, dict)
        and not prev_claude.get("error")
        and prev_claude.get("windows")
    ):
        last_good = (
            prev_claude.get("updatedAt")
            or prev_claude.get("staleSince")
            or prev_fetched
        )
        if not claude_due(last_good, now_iso, claude_min_seconds):
            skip_ids.add("claude")

    # Readers run concurrently (each ~10 s max) so one slow provider
    # cannot eat the shell's whole poll timeout; order stays READERS order.
    wanted = [
        (provider_id, reader)
        for provider_id, reader in READERS
        if provider_id not in disabled and provider_id not in skip_ids
    ]
    with ThreadPoolExecutor(max_workers=len(READERS)) as pool:
        partial = list(pool.map(lambda item: item[1](), wanted))
    fresh_by_id = {pid: result for (pid, _), result in zip(wanted, partial)}
    fresh = []
    for provider_id, _ in READERS:
        if provider_id in disabled:
            continue
        if provider_id in skip_ids:
            continue
        fresh.append(fresh_by_id[provider_id])

    merged, limited = merge_rate_limited(fresh, prev_providers, prev_fetched, now_iso)
    if skip_ids:
        # Skipped providers keep their previous snapshot verbatim (still
        # fresh enough to show); headline/events recompute below from it.
        merged_by_id = {p.get("id"): p for p in merged if isinstance(p, dict)}
        for provider_id, _ in READERS:
            if provider_id not in skip_ids:
                continue
            old = prev_by_id.get(provider_id)
            if isinstance(old, dict):
                kept = dict(old)
                if not kept.get("updatedAt"):
                    fallback = kept.get("staleSince") or prev_fetched
                    if fallback:
                        kept["updatedAt"] = fallback
                merged_by_id[provider_id] = kept
        merged = [
            merged_by_id[provider_id]
            for provider_id, _ in READERS
            if provider_id not in disabled and provider_id in merged_by_id
        ]
        # A skipped Claude must not trigger backoff: it was not fetched.
        limited = [pid for pid in limited if pid not in skip_ids]
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
    if args.seed:
        # Startup-silent: anything already true records its level with no alert.
        new_notified = seed_notified(merged, warn, crit)
        events = []

    document = {
        "fetchedAt": now_iso,
        "providers": merged,
        "events": events,
        "notified": new_notified,
        "limited": limited,
    }
    print(json.dumps(document, separators=(",", ":")))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
