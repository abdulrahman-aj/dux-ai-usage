"""Parser/normalizer behavior from small recorded, fully redacted fixtures."""

import json
import os
import sys
import threading
import time
from types import SimpleNamespace

import pytest

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "DuxAiUsage", "collectors")
)

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
            {
                "kind": "weekly_scoped",
                "group": "weekly",
                "percent": 0,
                "resets_at": "2026-11-16T21:59:59Z",
                "scope": {"model": {"display_name": "Fable"}},
            },
        ],
    }
    parsed = claude_reader.parse_usage(payload)
    by_id = {w["id"]: w for w in parsed}
    assert by_id["fiveHour"]["usedPercent"] == 17.0
    assert by_id["fiveHour"]["resetsAt"] == "2026-11-10T21:39:59Z"
    assert by_id["weekly"]["usedPercent"] == 3.0
    # Server values above 100 are clamped like the other providers.
    over = claude_reader.parse_usage({"five_hour": {"utilization": 140.5}})
    assert over[0]["usedPercent"] == 100.0
    scoped = by_id["weekly-fable"]
    assert scoped["label"] == "Weekly · Fable"
    assert scoped["usedPercent"] == 0.0


def test_claude_null_windows_tolerated():
    parsed = claude_reader.parse_usage(
        {
            "five_hour": {"utilization": None, "resets_at": None},
            "seven_day": None,
            "limits": [],
        }
    )
    by_id = {w["id"]: w for w in parsed}
    assert by_id["fiveHour"]["usedPercent"] is None
    assert by_id["fiveHour"]["resetsAt"] is None
    assert by_id["weekly"]["usedPercent"] is None
    # Non-dict payloads and scoped entries without usable data are skipped.
    assert claude_reader.parse_usage({}) != []
    assert claude_reader.parse_usage(None) == []


def test_claude_missing_credentials_is_hint_not_traceback():
    provider = claude_reader.fetch(credentials_path="/nonexistent/creds.json")
    assert provider["error"]["kind"] == "missing"


def test_codex_standard_plus_shape():
    result = {
        "rateLimits": {
            "limitId": "codex",
            "planType": "plus",
            "primary": {
                "usedPercent": 8,
                "windowDurationMins": 300,
                "resetsAt": 1794347250,
            },
            "secondary": {
                "usedPercent": 100,
                "windowDurationMins": 10080,
                "resetsAt": 1794568941,
            },
        },
        "rateLimitsByLimitId": {
            "codex": {
                "limitId": "codex",
                "planType": "plus",
                "primary": {
                    "usedPercent": 8,
                    "windowDurationMins": 300,
                    "resetsAt": 1794347250,
                },
                "secondary": {
                    "usedPercent": 100,
                    "windowDurationMins": 10080,
                    "resetsAt": 1794568941,
                },
            }
        },
        "rateLimitResetCredits": {"availableCount": 0, "credits": []},
    }
    parsed = codex_reader.parse_result(result)
    assert parsed["plan"] == "Codex Plus"
    assert [(w["id"], w["usedPercent"]) for w in parsed["windows"]] == [
        ("fiveHour", 8.0),
        ("weekly", 100.0),
    ]
    assert parsed["resets"] == {
        "available": 0,
        "url": "https://chatgpt.com/codex/settings/usage",
    }


def test_codex_weekly_only_plan_classifies_by_duration_not_slot():
    # Weekly-only plans return the weekly window as primary, secondary null.
    result = {
        "rateLimits": {
            "planType": "pro",
            "primary": {
                "usedPercent": 41,
                "windowDurationMins": 10080,
                "resetsAt": 1794568941,
            },
            "secondary": None,
        }
    }
    parsed = codex_reader.parse_result(result)
    assert [(w["id"], w["label"]) for w in parsed["windows"]] == [("weekly", "Weekly")]


def test_codex_slot_order_does_not_matter_and_monthly_supported():
    result = {
        "rateLimits": {
            "planType": "business",
            "primary": {
                "usedPercent": 12,
                "windowDurationMins": 10080,
                "resetsAt": 1794568941,
            },
            "secondary": {
                "usedPercent": 55,
                "windowDurationMins": 300,
                "resetsAt": 1794347250,
            },
        }
    }
    parsed = codex_reader.parse_result(result)
    assert [w["id"] for w in parsed["windows"]] == ["fiveHour", "weekly"]
    monthly = codex_reader.classify_window(
        {"usedPercent": 20, "windowDurationMins": 43200, "resetsAt": 1797000000}
    )
    assert (monthly["id"], monthly["label"]) == ("monthly", "Monthly")


def test_codex_error_mapping_distinguishes_auth_from_transient():
    signed_out = {"error": {"code": -32600, "message": "account auth required"}}
    assert codex_reader.fetch(run=lambda: signed_out)["error"]["kind"] == "auth"
    failed = {"error": {"code": -32000, "message": "boom"}}
    assert codex_reader.fetch(run=lambda: failed)["error"]["kind"] == "unavailable"
    for bad in ({}, None, {"result": {}}, {"result": None}):
        assert (
            codex_reader.fetch(run=lambda bad=bad: bad)["error"]["kind"]
            == "unavailable"
        ), bad
    missing = codex_reader.parse_result({})
    assert missing["windows"] == [] and missing["plan"] == ""


def test_rpc_deadline_survives_partial_line():
    # Partial line data must not wedge the reader: with the write end
    # held open (no EOF), only the deadline can end the wait.
    r, w = os.pipe()
    os.write(w, b'{"id":9,')

    class FakeStdin:
        def write(self, data):
            pass

        def flush(self):
            pass

    class FakeStdout:
        def fileno(self):
            return r

    proc = SimpleNamespace(stdin=FakeStdin(), stdout=FakeStdout())
    start = time.monotonic()
    try:
        with pytest.raises(TimeoutError):
            codex_reader._rpc(proc, 9, "x", timeout=0.6)
    finally:
        os.close(w)
        os.close(r)
    assert time.monotonic() - start >= 0.5


def test_rpc_reads_framed_response():
    r, w = os.pipe()
    body = json.dumps({"id": 3, "result": {"ok": True}}) + "\n"
    os.write(w, body.encode())
    os.close(w)

    class FakeStdin:
        def write(self, data):
            pass

        def flush(self):
            pass

    class FakeStdout:
        def fileno(self):
            return r

    try:
        message = codex_reader._rpc(
            SimpleNamespace(stdin=FakeStdin(), stdout=FakeStdout()),
            3,
            "x",
            timeout=5,
        )
    finally:
        os.close(r)
    assert message == {"id": 3, "result": {"ok": True}}


def test_go_payload_parses_all_windows():
    payload = {
        "usage": {
            "rolling": {
                "status": "ok",
                "percent": 13,
                "resetsAt": "2026-11-10T21:52:35.000Z",
            },
            "weekly": {
                "status": "ok",
                "percent": 88,
                "resetsAt": "2026-11-16T00:00:00.000Z",
            },
            "monthly": {
                "status": "ok",
                "percent": 88,
                "resetsAt": "2026-11-18T16:11:55.000Z",
            },
        }
    }
    windows = go_reader.parse_usage(payload)
    assert [(w["id"], w["usedPercent"]) for w in windows] == [
        ("rolling", 13.0),
        ("weekly", 88.0),
        ("monthly", 88.0),
    ]
    assert go_reader.parse_usage({}) == []


def test_go_rate_limited_window_counts_as_exhausted():
    windows = go_reader.parse_usage(
        {
            "usage": {
                "rolling": {
                    "status": "rate-limited",
                    "percent": 4,
                    "resetsAt": "2026-11-10T21:52:35.000Z",
                },
            }
        }
    )
    assert windows[0]["usedPercent"] == 100.0


def test_go_rate_limited_without_percent_still_exhausted():
    windows = go_reader.parse_usage(
        {
            "usage": {
                "rolling": {
                    "status": "rate-limited",
                    "resetsAt": "2026-11-10T21:52:35.000Z",
                },
            }
        }
    )
    assert [(w["id"], w["usedPercent"]) for w in windows] == [("rolling", 100.0)]


def test_go_missing_key_is_hint():
    provider = go_reader.fetch(path="/nonexistent/opencode.db")
    assert provider["error"]["kind"] == "missing"


def _redirect_server():
    """Local server: every path but /target answers 302 to /target."""
    from http.server import BaseHTTPRequestHandler, HTTPServer

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path == "/target":
                body = b"{}"
                self.send_response(200)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            else:
                self.send_response(302)
                self.send_header("Location", "/target")
                self.end_headers()

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return server


@pytest.mark.parametrize(
    "module,attr,value,kwargs",
    [
        (claude_reader, "API_URL", "http://127.0.0.1:%d/redir", {"token": "dummy"}),
        (go_reader, "BASE_URL", "http://127.0.0.1:%d", {"key": "dummy"}),
    ],
)
def test_redirect_is_unavailable_not_followed(monkeypatch, module, attr, value, kwargs):
    server = _redirect_server()
    monkeypatch.setattr(module, attr, value % server.server_port)
    try:
        provider = module.fetch(**kwargs)
    finally:
        server.shutdown()
        server.server_close()
    assert provider["error"]["kind"] == "unavailable"


def test_claude_resets_none_when_nothing_banked():
    assert claude_reader.parse_resets({}) is None
    assert claude_reader.parse_resets(None) is None
    empty = {
        "cedar_ember": {"grants": []},
        "juniper_tide": {"available": False, "resets_per_week": 1},
    }
    assert claude_reader.parse_resets(empty) is None


def test_claude_resets_counts_grants_and_weekly():
    payload = {
        "cedar_ember": {
            "grants": [
                {
                    "label": "Fable reset",
                    "resets_left": 1,
                    "usable_now": True,
                    "ends_at": "2026-11-20T00:00:00Z",
                },
                {"label": "Spent", "resets_left": 0},
                {"label": "Paused", "resets_left": 1, "paused": True},
            ],
        },
        "juniper_tide": {
            "available": True,
            "next_available_at": "2026-11-18T00:00:00Z",
        },
    }
    resets = claude_reader.parse_resets(payload)
    assert resets["available"] == 2
    assert "Fable reset" in resets["label"] and "weekly reset" in resets["label"]
    assert resets["resetsAt"] == "2026-11-20T00:00:00Z"
