import QtQuick
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

// Shared poller: the only surface that runs the collector. Every other
// surface reads the snapshot from the "duxAiSnapshot" global var (seeded
// from persisted plugin state so reloads show last-known values at once).
// Critical/reset alerts go out as freedesktop notifications (notify-send,
// proven live against Dux's notification centre); the crossing rules
// themselves live in collectors/model.py (unit-tested).
PluginComponent {
    id: root

    readonly property int pollMinutes: Math.max(2, Math.round(pluginData.pollMinutes ?? 5))
    readonly property bool enableClaude: pluginData.enableClaude ?? true
    readonly property bool enableCodex: pluginData.enableCodex ?? true
    readonly property bool enableGo: pluginData.enableGo ?? true
    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100
    readonly property bool notificationsOn: pluginData.toastsEnabled ?? true
    readonly property bool resetNotifyOn: pluginData.resetNotify ?? true

    property var snapshot: null
    property var notified: ({})
    // First successful poll after startup records current levels
    // silently (--seed): anything already true while the shell was off
    // must not alert, or every restart re-fires known states.
    property bool seeded: false
    property int backoffMinutes: 0
    property bool busy: false
    property bool refreshQueued: false
    // Last poll start (ms): manual Refresh debounces against it so rapid
    // clicks across the pill/popout/dash/desktop buttons cannot each burn
    // the shared Claude token budget.
    property double lastPollStartMs: 0

    // Claude shares its OAuth token with every running Claude Code
    // session, so the collector refetches it at most every 10 minutes
    // (collectors/model.CLAUDE_MIN_SECONDS): a recent good Claude fetch
    // is reused while Codex/Go poll on the normal schedule. Manual
    // refresh gets the same per-provider debounce for free.

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
        // Per-provider debounce lives in the collector (Claude minimum
        // interval); this global 60 s guard stops rapid Refresh clicks
        // from re-polling Codex/Go either. The timer is not restarted on
        // a debounced click so the scheduled rhythm holds.
        if (Date.now() - root.lastPollStartMs < 60000)
            return;
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
        root.lastPollStartMs = Date.now();
        var args = ["python3", root.collectorPath, "--warn", String(root.warnAt), "--crit", String(root.critAt)];
        var disabled = root.disabledIds();
        if (disabled.length > 0)
            args.push("--disable", disabled.join(","));
        if (!root.resetNotifyOn)
            args.push("--no-reset-notify");
        if (!root.seeded)
            args.push("--seed");
        if (root.snapshot)
            args.push("--prev", JSON.stringify(root.snapshot));
        if (root.seeded && Object.keys(root.notified).length > 0)
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
            if (doc.limited && doc.limited.length > 0) {
                // Exponential backoff (doubling, 30 min cap), floored at
                // the server's Retry-After hint when one was served. A 0
                // hint (what Anthropic sends on persistent per-token 429s)
                // is not a wait: the doubling floor applies instead, and
                // the collector skips Claude until the minimum elapses.
                var needMinutes = 0;
                for (var i = 0; i < doc.providers.length; i++) {
                    var hintSec = doc.providers[i].retryAfterSec;
                    if (hintSec > 0)
                        needMinutes = Math.max(needMinutes, Math.ceil(hintSec / 60));
                }
                var grown = Math.min((root.backoffMinutes || root.pollMinutes) * 2, 30);
                root.backoffMinutes = Math.min(Math.max(grown, needMinutes, 1), 30);
            } else {
                root.backoffMinutes = 0;
            }
            root.snapshot = {
                "providers": doc.providers,
                "fetchedAt": doc.fetchedAt,
                "limited": doc.limited ?? [],
                "backoffMinutes": root.backoffMinutes,
                "pollMinutes": root.pollMinutes
            };
            root.notified = doc.notified ?? {};
            root.seeded = true;
            pluginService.savePluginState(pluginId, "snapshot", root.snapshot);
            pluginService.savePluginState(pluginId, "notified", root.notified);
            snapshotVar.set(root.snapshot);
            if (root.notificationsOn)
                fireNotifications(doc.events ?? []);
            if (root.refreshQueued) {
                root.refreshQueued = false;
                poll();
            }
        }, undefined, 90000, root);
    }

    // Alerts are freedesktop notifications, one per crossing: critical
    // when a window hits its critical threshold, reset when an
    // exhausted window becomes usable again. Warning levels stay on the
    // pill only. Delivery is notify-send, verified live against Dux's
    // notification centre: -a shows the "AI Usage" name, -i the
    // provider logo, and -A renders an "Open usage page" button whose
    // click returns "open" to the waiting sender (critical stays up until
    // dismissed, reset uses the normal timeout).
    function fireNotifications(events) {
        for (var i = 0; i < events.length; i++) {
            let event = events[i];
            if (event.level !== "crit" && event.level !== "reset")
                continue;
            var pct = (event.usedPercent === null || event.usedPercent === undefined) ? "" : (" at " + Math.round(event.usedPercent) + "%");
            var summary = "";
            var body = "";
            var urgency = "normal";
            if (event.level === "crit") {
                urgency = "critical";
                // "Exhausted" only at a genuinely full window; a lower
                // critical threshold is "at the critical threshold".
                if ((event.usedPercent ?? 0) >= 100) {
                    summary = event.providerName + " " + event.windowLabel + " exhausted";
                    body = "Quota window is full" + pct + ". It resets " + resetText(event) + ".";
                } else {
                    summary = event.providerName + " " + event.windowLabel + " at critical threshold";
                    body = "Over the critical threshold" + pct + ". It resets " + resetText(event) + ".";
                }
            } else {
                summary = event.providerName + " " + event.windowLabel + " reset";
                body = "Fresh quota window started.";
            }
            var icon = (pluginService?.getPluginPath(pluginId) ?? "") + "/assets/" + shared.logoName(event.providerId) + ".svg";
            var args = ["notify-send", "-a", "AI Usage", "-i", icon, "-u", urgency, "-A", "open=Open usage page", summary, body];
            // -A implies --wait: the click lands here as "open". No
            // runCommand id: Proc nulls a shared id's callback when any
            // concurrent notification completes, which would drop a
            // later click; a random id keeps each waiter independent and
            // is cleaned up automatically.
            Proc.runCommand(undefined, args, function (stdout, exitCode) {
                if ((stdout ?? "").trim() === "open")
                    openUsagePage(event.providerId);
            }, undefined, Proc.noTimeout, root);
        }
    }

    function openUsagePage(providerId) {
        var providers = root.snapshot?.providers ?? [];
        for (var i = 0; i < providers.length; i++) {
            if (providers[i].id === providerId && providers[i].usageUrl) {
                Qt.openUrlExternally(providers[i].usageUrl);
                return;
            }
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
        // Stagger the first poll so shell startup stays fast — but when
        // the cached snapshot is still fresh, wait out the remainder of
        // the interval instead of refetching 15 s after every restart.
        // Date.parse yields NaN for a missing stamp, which fails the
        // range check and keeps the 15 s stagger.
        var delayMs = 15000;
        var ageMs = Date.now() - Date.parse(root.snapshot?.fetchedAt);
        var intervalMs = root.pollMinutes * 60000;
        if (ageMs >= 0 && ageMs < intervalMs)
            delayMs = intervalMs - ageMs;
        firstPoll.interval = delayMs;
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
        onTriggered: {
            // Align the periodic timer to this poll so it cannot fire a
            // second full poll right after a delayed first poll.
            pollTimer.restart();
            root.poll();
        }
    }
}
