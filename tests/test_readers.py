"""Parser/normalizer behavior from small recorded, fully redacted fixtures."""

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "DuxAiUsage", "collectors"))

import claude_reader
import codex_reader
import go_reader


def test_claude_full_payload_parses_windows_and_plan():
    payload = {
        "five_hour": {"utilization": 17.0, "resets_at": "2026-11-10T21:39:59Z"},
        "seven_day": {"utilization": 3.0, "resets_at": "2026-11-16T21:59:59Z"},
        "seven_day_opus": None,
        "seven_day_sonnet": None,
        "extra_usage": {"is_enabled": False},
        "limits": [
            {"kind": "session", "group": "session", "percent": 17},
            {"kind": "weekly_all", "group": "weekly", "percent": 3},
            {"kind": "weekly_scoped", "group": "weekly", "percent": 0,
             "resets_at": "2026-11-16T21:59:59Z",
             "scope": {"model": {"display_name": "Fable"}}},
        ],
        "subscriptionType": "pro",
    }
    parsed = claude_reader.parse_usage(payload)
    assert parsed["plan"] == "Pro"
    by_id = {w["id"]: w for w in parsed["windows"]}
    assert by_id["fiveHour"]["usedPercent"] == 17.0
    assert by_id["fiveHour"]["resetsAt"] == "2026-11-10T21:39:59Z"
    assert by_id["weekly"]["usedPercent"] == 3.0
    scoped = by_id["weekly-fable"]
    assert scoped["label"] == "Weekly · Fable"
    assert scoped["usedPercent"] == 0.0


def test_claude_null_windows_tolerated():
    parsed = claude_reader.parse_usage({
        "five_hour": {"utilization": None, "resets_at": None},
        "seven_day": None,
        "limits": [],
    })
    by_id = {w["id"]: w for w in parsed["windows"]}
    assert by_id["fiveHour"]["usedPercent"] is None
    assert by_id["fiveHour"]["resetsAt"] is None
    assert by_id["weekly"]["usedPercent"] is None
    # Non-dict payloads and scoped entries without usable data are skipped.
    assert claude_reader.parse_usage({})["windows"] != []
    assert claude_reader.parse_usage(None) == {"plan": "", "windows": []}


def test_claude_missing_credentials_is_hint_not_traceback():
    provider = claude_reader.fetch(credentials_path="/nonexistent/creds.json")
    assert provider["error"]["kind"] == "missing"
    assert "Sign in" in provider["error"]["hint"]


def test_codex_standard_plus_shape():
    result = {
        "rateLimits": {
            "limitId": "codex",
            "planType": "plus",
            "primary": {"usedPercent": 8, "windowDurationMins": 300,
                        "resetsAt": 1794347250},
            "secondary": {"usedPercent": 100, "windowDurationMins": 10080,
                          "resetsAt": 1794568941},
        },
        "rateLimitsByLimitId": {"codex": {
            "limitId": "codex",
            "planType": "plus",
            "primary": {"usedPercent": 8, "windowDurationMins": 300,
                        "resetsAt": 1794347250},
            "secondary": {"usedPercent": 100, "windowDurationMins": 10080,
                          "resetsAt": 1794568941},
        }},
        "rateLimitResetCredits": {"availableCount": 0, "credits": []},
    }
    parsed = codex_reader.parse_result(result)
    assert parsed["plan"] == "Codex Plus"
    assert [(w["id"], w["usedPercent"]) for w in parsed["windows"]] == [
        ("fiveHour", 8.0), ("weekly", 100.0)]
    assert parsed["resets"] == {
        "available": 0, "url": "https://chatgpt.com/codex/settings/usage"}


def test_codex_weekly_only_plan_classifies_by_duration_not_slot():
    # Weekly-only plans return the weekly window as primary, secondary null.
    result = {"rateLimits": {
        "planType": "pro",
        "primary": {"usedPercent": 41, "windowDurationMins": 10080,
                    "resetsAt": 1794568941},
        "secondary": None,
    }}
    parsed = codex_reader.parse_result(result)
    assert [(w["id"], w["label"]) for w in parsed["windows"]] == [
        ("weekly", "Weekly")]


def test_codex_slot_order_does_not_matter_and_monthly_supported():
    result = {"rateLimits": {
        "planType": "business",
        "primary": {"usedPercent": 12, "windowDurationMins": 10080,
                    "resetsAt": 1794568941},
        "secondary": {"usedPercent": 55, "windowDurationMins": 300,
                      "resetsAt": 1794347250},
    }}
    parsed = codex_reader.parse_result(result)
    assert [w["id"] for w in parsed["windows"]] == ["fiveHour", "weekly"]
    monthly = codex_reader.classify_window(
        {"usedPercent": 20, "windowDurationMins": 43200, "resetsAt": 1797000000})
    assert (monthly["id"], monthly["label"]) == ("monthly", "Monthly")


def test_codex_empty_result_is_auth_hint():
    assert codex_reader.fetch(run=lambda: {})["error"]["kind"] == "auth"
    assert codex_reader.fetch(run=lambda: None)["error"]["kind"] == "auth"
    missing = codex_reader.parse_result({})
    assert missing["windows"] == [] and missing["plan"] == ""


def test_go_payload_parses_all_windows():
    payload = {"usage": {
        "rolling": {"status": "ok", "percent": 13,
                    "resetsAt": "2026-11-10T21:52:35.000Z"},
        "weekly": {"status": "ok", "percent": 88,
                   "resetsAt": "2026-11-16T00:00:00.000Z"},
        "monthly": {"status": "ok", "percent": 88,
                    "resetsAt": "2026-11-18T16:11:55.000Z"},
    }}
    windows = go_reader.parse_usage(payload)
    assert [(w["id"], w["usedPercent"]) for w in windows] == [
        ("rolling", 13.0), ("weekly", 88.0), ("monthly", 88.0)]
    assert go_reader.parse_usage({}) == []


def test_go_rate_limited_window_counts_as_exhausted():
    windows = go_reader.parse_usage({"usage": {
        "rolling": {"status": "rate-limited", "percent": 4,
                    "resetsAt": "2026-11-10T21:52:35.000Z"},
    }})
    assert windows[0]["usedPercent"] == 100.0


def test_go_missing_key_is_hint():
    provider = go_reader.fetch(path="/nonexistent/opencode.db")
    assert provider["error"]["kind"] == "missing"
    assert "/connect" in provider["error"]["hint"]
