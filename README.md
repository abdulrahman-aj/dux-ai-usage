# dux-ai-usage

Composite Dux shell plugin showing AI subscription usage for **Claude**
(Claude Code subscription), **Codex** (ChatGPT plan) and **OpenCode Go**
(single workspace: the key OpenCode already stores).

Surfaces: bar pill + popout, Dash tab, Dash Overview card, desktop widget,
settings page, critical/reset notifications. See `DuxAiUsage/plugin.json` for the manifest.

## Develop

Enter the dev shell (Python + pytest + ruff):

```sh
nix develop
```

Run checks (also wired into CI-less local flow; run before every PR):

```sh
make lint   # ruff check + format check over collectors/ and tests/
make test   # pytest, parser/normalizer + threshold-event behavior
```

Screenshot every surface at every density (run it on a test desktop,
never one in use; it backs up and restores the Dux settings it touches):

```sh
make shots OUT=~/shots   # scripts/capture-shots.sh
```

## Install on a live Dux session

```sh
mkdir -p ~/.config/dms/plugins
ln -s "$PWD/DuxAiUsage" ~/.config/dms/plugins/DuxAiUsage
dms ipc call plugin-scan rescan duxAiUsage
dms ipc call plugins enable duxAiUsage
```

Reload after edits (no reboot):

```sh
dms ipc call plugins reload duxAiUsage
```

## Data layer

`DuxAiUsage/collectors/collect.py` prints one normalized JSON document:

```json
{"fetchedAt": "...", "providers": [{"id": "...", "name": "...", "plan": "...",
 "stale": false, "updatedAt": "...", "retryAfterSec": 90,
 "headlineId": "weekly", "headlineShort": false, "usageUrl": "...",
 "windows": [{"id": "...", "label": "...", "usedPercent": 17.0, "resetsAt": "..."}],
 "resets": {"available": 0, "url": "..."} | null,
 "error": null | {"kind": "missing|auth|rateLimited|unavailable", "hint": "...", "retryAfter": 90}}],
 "events": [...], "notified": {...}, "limited": [...]}
```

Rules:

- Read-only against every account. Never writes or refreshes credentials
  itself (spawning `codex app-server` lets Codex refresh its own token
  file, serialized by its own lock); never prints secrets (run with
  redacted output only).
- One shared poller: the daemon component polls; pills/cards/tabs read the
  shared snapshot. Polling is gentle (default 5 min, minimum 2 min) with
  backoff on HTTP 429 that honors the server's Retry-After hint. Claude
  shares its token with every running Claude Code session, so it refetches
  at most every 10 minutes (a recent good fetch is reused; manual Refresh
  debounces per provider plus a 60 s global guard, and restarts wait out a
  fresh cache instead of refetching). After a 429 the next Claude attempt
  waits out the Retry-After hint too (or the same 10 minutes when the hint
  is 0/absent, which Anthropic sends on persistent per-token 429s), so a
  manual Refresh cannot hammer the shared budget either. Rate-limited
  providers keep last-known values with their own updatedAt plus a short
  note ("Limiting usage checks · updated 17m ago"); unreachable ones keep
  values with just the age. Opening the bar popout or the AI Usage Dash tab refreshes whatever providers are due (same debounces apply).
- The pill headlines one window per provider (long window by default; a
  shorter window at/above warn takes over; see collectors/model.py).
  Unused Claude per-model rows ("Weekly · Fable" at 0%) stay out of the
  snapshot.
- Banked resets are display-only with a quiet usage-page link (prominent
  only when resets are banked). Nothing is ever redeemed automatically.
- All QML formatting (colors, headline, stale/updated text) lives in one
  place: DuxAiUsage/AiUsageShared.qml, used by every surface.

## Shell quirks found while building (Dux 2.1.1)

- `PluginGlobalVar` lives in `qs.Widgets`, not `qs.Modules.Plugins` (docs say
  the latter).
- On the default island bar, center widgets are replaced by island
  activities: a bar pill only renders in the left/right sections. Verify the
  pill there.
- Plugin `.js` libraries and shared `.qml` includes are cached from shell
  startup and ignore `plugins reload`; only manifest components hot-reload.
  The shared formatting helper (AiUsageShared.qml) therefore needs a shell
  restart to pick up edits; the threshold rules stay in one tested place:
  `collectors/model.py`.
- Dash tab panels snap to whole 96px grid rows (two at least) that ignore
  density, so a plugin cannot make the panel hug short content. The tab
  instead stretches its cards to the panel's bottom edge, while reporting
  its natural height so the panel can still shrink.
- The overview card slot injects `pluginId`/`pluginService` only once at
  load, which can race; the card reads the singletons directly instead.
- External edits to `plugin_settings.json` are not re-parsed live (no
  `onFileChanged` handler upstream). Change settings via Settings → Plugins
  UI; hand edits apply after a shell restart.
