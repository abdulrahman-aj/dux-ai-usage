import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Shared poller: the only surface that runs the collector. Every other
// surface reads the snapshot from the "duxAiSnapshot" global var (seeded
// from persisted plugin state so reloads show last-known values at once).
// Threshold toasts fire here from the collector's events; the crossing
// rules themselves live in collectors/model.py (unit-tested).
PluginComponent {
    id: root

    readonly property int pollMinutes: Math.max(2, Math.round(pluginData.pollMinutes ?? 5))
    readonly property bool enableClaude: pluginData.enableClaude ?? true
    readonly property bool enableCodex: pluginData.enableCodex ?? true
    readonly property bool enableGo: pluginData.enableGo ?? true
    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100
    readonly property bool toastsOn: pluginData.toastsEnabled ?? true
    readonly property bool resetNotifyOn: pluginData.resetNotify ?? true

    property var snapshot: null
    property var notified: ({})
    property int backoffMinutes: 0
    property bool busy: false
    property bool refreshQueued: false

    readonly property string collectorPath: (pluginService?.getPluginPath(pluginId) ?? "") + "/collectors/collect.py"

    PluginGlobalVar {
        id: snapshotVar
        varName: "duxAiSnapshot"
        defaultValue: null
    }

    PluginGlobalVar {
        varName: "duxAiRefresh"
        defaultValue: 0
        onValueChanged: root.pollNow()
    }

    function disabledIds() {
        var ids = [];
        if (!root.enableClaude)
            ids.push("claude");
        if (!root.enableCodex)
            ids.push("codex");
        if (!root.enableGo)
            ids.push("opencodeGo");
        return ids;
    }

    function pollNow() {
        pollTimer.restart();
        if (root.busy) {
            // A collector run is in flight; run once more when it lands.
            root.refreshQueued = true;
            return;
        }
        poll();
    }

    function poll() {
        if (root.busy || !pluginService || !root.collectorPath)
            return;
        root.busy = true;
        var args = ["python3", root.collectorPath, "--warn", String(root.warnAt), "--crit", String(root.critAt)];
        var disabled = root.disabledIds();
        if (disabled.length > 0)
            args.push("--disable", disabled.join(","));
        if (!root.resetNotifyOn)
            args.push("--no-reset-notify");
        if (root.snapshot)
            args.push("--prev", JSON.stringify(root.snapshot));
        if (Object.keys(root.notified).length > 0)
            args.push("--notified", JSON.stringify(root.notified));
        // Readers run concurrently (~10 s each worst case); 90 s covers
        // the whole poll with headroom. Owner drops late callbacks after
        // teardown. No watchdog: a late answer self-heals via busy/queue.
        Proc.runCommand("duxAiUsage.collect", args, (stdout, exitCode) => {
            root.busy = false;
            if (exitCode !== 0) {
                root.refreshQueued = false;
                return;
            }
            var doc = null;
            try {
                doc = JSON.parse(stdout);
            } catch (e) {
                root.refreshQueued = false;
                return;
            }
            if (!doc || !doc.providers) {
                root.refreshQueued = false;
                return;
            }
            root.snapshot = {"providers": doc.providers, "fetchedAt": doc.fetchedAt};
            root.notified = doc.notified ?? {};
            pluginService.savePluginState(pluginId, "snapshot", root.snapshot);
            pluginService.savePluginState(pluginId, "notified", root.notified);
            snapshotVar.set(root.snapshot);
            if (doc.limited && doc.limited.length > 0)
                root.backoffMinutes = Math.min((root.backoffMinutes || root.pollMinutes) * 2, 30);
            else
                root.backoffMinutes = 0;
            if (root.toastsOn)
                fireToasts(doc.events ?? []);
            if (root.refreshQueued) {
                root.refreshQueued = false;
                poll();
            }
        }, undefined, 90000, root);
    }

    function fireToasts(events) {
        for (var i = 0; i < events.length; i++) {
            var event = events[i];
            var pct = (event.usedPercent === null || event.usedPercent === undefined) ? "" : (" at " + Math.round(event.usedPercent) + "%");
            var when = resetText(event);
            if (event.level === "crit") {
                // "Exhausted" only at a genuinely full window; a lower
                // critical threshold is "at the critical threshold".
                if ((event.usedPercent ?? 0) >= 100)
                    ToastService.showError(event.providerName + " " + event.windowLabel + " exhausted" + pct, "Quota window is full. It resets " + when + ".");
                else
                    ToastService.showError(event.providerName + " " + event.windowLabel + " at the critical threshold" + pct, "Over the critical threshold. It resets " + when + ".");
            } else if (event.level === "warn")
                ToastService.showWarning(event.providerName + " " + event.windowLabel + pct, "Over the warning threshold. Resets " + when + ".");
            else
                ToastService.showInfo(event.providerName + " " + event.windowLabel + " reset", "Fresh quota window started.");
        }
    }

    function resetText(event) {
        var resetsAt = null;
        var providers = root.snapshot?.providers ?? [];
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].id !== event.providerId)
                continue;
            var windows = providers[i].windows ?? [];
            for (var j = 0; j < windows.length; j++) {
                if (windows[j].id === event.windowId)
                    resetsAt = windows[j].resetsAt;
            }
        }
        if (!resetsAt)
            return "soon";
        try {
            var cd = shared.countdown(resetsAt);
            return (!cd || cd === "soon") ? "soon" : "in " + cd;
        } catch (e) {
            return "soon";
        }
    }

    // Countdown text comes from the same shared helper every surface
    // uses.
    AiUsageShared {
        id: shared
    }

    Timer {
        id: pollTimer
        interval: (root.backoffMinutes || root.pollMinutes) * 60000
        repeat: true
        running: true
        onTriggered: root.poll()
    }

    // The host injects pluginService after creation; state must load
    // once it is present, or the first poll would run with empty
    // prev/notified and re-fire every threshold toast. A one-shot
    // retry timer avoids clashing with the base type's own
    // onPluginServiceChanged handler.
    property bool savedLoaded: false

    function loadSaved() {
        if (root.savedLoaded || !pluginService || !pluginId)
            return;
        root.savedLoaded = true;
        var saved = pluginService.loadPluginState(pluginId, "snapshot", null) ?? null;
        if (saved)
            root.snapshot = saved;
        root.notified = pluginService.loadPluginState(pluginId, "notified", {}) ?? {};
        if (root.snapshot)
            snapshotVar.set(root.snapshot);
        // Stagger the first poll so shell startup stays fast.
        firstPoll.start();
    }

    Timer {
        id: savedLoader
        interval: 1000
        repeat: true
        running: !root.savedLoaded
        onTriggered: root.loadSaved()
    }

    Component.onCompleted: root.loadSaved()

    Timer {
        id: firstPoll
        interval: 15000
        repeat: false
        onTriggered: root.poll()
    }
}
