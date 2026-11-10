# dux-ai-usage

Composite Dux shell plugin showing AI subscription usage for **Claude**
(Claude Code subscription), **Codex** (ChatGPT plan) and **OpenCode Go**
(single workspace: the key OpenCode already stores).

Surfaces: bar pill + popout, Dash tab, Dash Overview card, desktop widget,
settings page, threshold toasts. See `DuxAiUsage/plugin.json` for the manifest.

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
 "stale": false, "headlineId": "weekly", "headlineShort": false, "usageUrl": "...",
 "windows": [{"id": "...", "label": "...", "usedPercent": 17.0, "resetsAt": "..."}],
 "resets": {"available": 0, "url": "..."} | null,
 "error": null | {"kind": "missing|auth|rateLimited|unavailable", "hint": "..."}}],
 "events": [...], "notified": {...}, "limited": [...]}
```

Rules:

- Read-only against every account. Never writes or refreshes credentials
  itself (spawning `codex app-server` lets Codex refresh its own token
  file, serialized by its own lock); never prints secrets (run with
  redacted output only).
- One shared poller: the daemon component polls; pills/cards/tabs read the
  shared snapshot. Polling is gentle (default 5 min, minimum 2 min) with
  backoff on HTTP 429. Rate-limited or unreachable providers keep
  last-known values (marked stale with their original fetch, so the tag
  shows only when actually stale, with its age).
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
- The overview card slot injects `pluginId`/`pluginService` only once at
  load, which can race; the card reads the singletons directly instead.
- External edits to `plugin_settings.json` are not re-parsed live (no
  `onFileChanged` handler upstream). Change settings via Settings → Plugins
  UI; hand edits apply after a shell restart.
