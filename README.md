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
 "windows": [{"id": "...", "label": "...", "usedPercent": 17.0, "resetsAt": "..."}],
 "resets": {"available": 0, "url": "..."} | null,
 "error": null | {"kind": "missing|auth|rateLimited|unavailable", "hint": "..."}}],
 "events": [...], "notified": {...}, "limited": [...]}
```

Rules:

- Read-only against every account. Never writes credential files or DBs,
  never refreshes tokens itself, never prints secrets (run with redacted
  output only).
- One shared poller: the daemon component polls; pills/cards/tabs read the
  shared snapshot. Polling is gentle (default 5 min, minimum 2 min) with
  backoff on HTTP 429, keeping last-known values.
- Banked resets are display-only with a button that opens the provider's
  usage page for manual confirmation. Nothing is ever redeemed automatically.

## Shell quirks found while building (Dux 2.1.1)

- `PluginGlobalVar` lives in `qs.Widgets`, not `qs.Modules.Plugins` (docs say
  the latter).
- On the default island bar, center widgets are replaced by island
  activities: a bar pill only renders in the left/right sections. Verify the
  pill there.
- Plugin `.js` libraries and shared `.qml` includes are cached from shell
  startup and ignore `plugins reload`; only manifest components hot-reload.
  This plugin therefore inlines its formatting helpers per surface (the
  threshold rules stay in one tested place: `collectors/model.py`).
- The overview card slot injects `pluginId`/`pluginService` only once at
  load, which can race; the card reads the singletons directly instead.
- External edits to `plugin_settings.json` are not re-parsed live (no
  `onFileChanged` handler upstream). Change settings via Settings → Plugins
  UI; hand edits apply after a shell restart.
