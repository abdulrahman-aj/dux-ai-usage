#!/usr/bin/env bash
# Capture every plugin surface at every Dux density on the CURRENT
# desktop (run it on the machine whose shell you want to photograph,
# e.g. msi-dux over `tailscale ssh ... bash -lc`). Never run it on a
# desktop someone is using: it opens popouts and the Dash, flips the
# density and adds a temporary desktop widget.
#
# Usage: capture-shots.sh OUT_DIR [density ...]
#   densities default to: spacious comfortable compact dense
#
# Side effects, all undone on exit (also on error):
#   - settings.json is backed up and restored byte-for-byte, which puts
#     back the density and removes the temporary desktop widget;
#   - session.json (desktop widget positions) likewise.
# niri copies each screenshot to the clipboard; that is not undone.
set -euo pipefail

out=${1:?usage: capture-shots.sh OUT_DIR [density ...]}
shift
densities=("$@")
[ ${#densities[@]} -gt 0 ] || densities=(spacious comfortable compact dense)

export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
export WAYLAND_DISPLAY=${WAYLAND_DISPLAY:-wayland-1}
NIRI_SOCKET=$(ls "$XDG_RUNTIME_DIR"/niri."$WAYLAND_DISPLAY".*.sock | head -1)
export NIRI_SOCKET

settings=$HOME/.config/dms/settings.json
session=$HOME/.local/state/dms/session.json
shots=$HOME/Pictures/Screenshots
mkdir -p "$out" "$shots"
backup=$(mktemp -d)
cp -p "$settings" "$backup/settings.json"
cp -p "$session" "$backup/session.json"

popout_open=false

restore() {
    if $popout_open; then
        dms ipc call widget toggle duxAiUsage >/dev/null 2>&1 || true
    fi
    dms ipc call dash close >/dev/null 2>&1 || true
    dms ipc call control-center hide >/dev/null 2>&1 || true
    # dms writes these files itself (e.g. after the last density change);
    # copy, let it settle, and copy again if one of its writes landed late.
    local f
    for _ in 1 2 3; do
        cp -p "$backup/settings.json" "$settings"
        cp -p "$backup/session.json" "$session"
        sleep 2
        f=ok
        cmp -s "$backup/settings.json" "$settings" || f=retry
        cmp -s "$backup/session.json" "$session" || f=retry
        [ "$f" = ok ] && break
    done
    echo "restored: density=$(dms ipc call settings get density)"
    cmp "$backup/settings.json" "$settings" && echo "settings.json identical to backup"
    cmp "$backup/session.json" "$session" && echo "session.json identical to backup"
}
trap restore EXIT

# Newest file in the screenshot dir. sed reads the whole listing, so a
# big directory cannot SIGPIPE `ls` (fatal under pipefail) like head.
newest() {
    ls -t "$shots" | sed -n 1p
}

# niri writes to the screenshot-path; wait for the new file, move it.
shot() {
    local before latest
    # Hide the previous shot's "Screenshot captured" toast (popups only;
    # the notification history is untouched).
    dms ipc call notifications dismissAllPopups >/dev/null
    sleep 0.5
    before=$(newest)
    niri msg action screenshot-screen --write-to-disk true --show-pointer false
    for _ in $(seq 40); do
        sleep 0.25
        latest=$(newest)
        [ "$latest" != "$before" ] && break
    done
    if [ -z "$latest" ] || [ "$latest" = "$before" ]; then
        echo "no screenshot appeared for $1 (check niri's screenshot-path)" >&2
        exit 1
    fi
    sleep 0.5
    mv "$shots/$latest" "$out/$1.png"
    echo "shot $1"
}

# Temporary desktop widget at its default size (lands in "small" mode).
tmp=$(mktemp)
jq '.desktopWidgetInstances += [{"id": "dw_aiusage_shots", "widgetType": "duxAiUsage", "name": "AI Usage", "enabled": true, "config": {}}]' "$settings" >"$tmp"
cat "$tmp" >"$settings"
rm -f "$tmp"
sleep 3

for d in "${densities[@]}"; do
    dms ipc call settings set density "$d" >/dev/null
    sleep 2
    shot "desktop-$d"
    dms ipc call widget toggle duxAiUsage >/dev/null
    popout_open=true
    sleep 1.5
    shot "popout-$d"
    dms ipc call widget toggle duxAiUsage >/dev/null
    popout_open=false
    sleep 1
    dms ipc call dash open plugin_duxAiUsage >/dev/null
    sleep 2
    shot "dash-$d"
    dms ipc call dash open overview >/dev/null
    sleep 2
    shot "ref-dash-overview-$d"
    dms ipc call dash close >/dev/null
    sleep 1
    dms ipc call control-center open >/dev/null
    sleep 2
    shot "ref-control-center-$d"
    dms ipc call control-center hide >/dev/null
    sleep 1
done
