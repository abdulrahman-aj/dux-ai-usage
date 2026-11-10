import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins

// Bar pill (both orientations) + popout: per-provider compact windows,
// colored by thresholds. One shared poller lives in Daemon.qml; this
// surface only reads the "duxAiSnapshot" global var.
PluginComponent {
    id: root

    property double headerNowMs: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.headerNowMs = Date.now()
    }

    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100
    readonly property bool showClaude: pluginData.enableClaude ?? true
    readonly property bool showCodex: pluginData.enableCodex ?? true
    readonly property bool showGo: pluginData.enableGo ?? true

    PluginGlobalVar {
        id: snapshotVar
        varName: "duxAiSnapshot"
        defaultValue: null
    }

    PluginGlobalVar {
        id: refreshVar
        varName: "duxAiRefresh"
        defaultValue: 0
    }

    readonly property var snapshot: snapshotVar.value
    readonly property var providers: {
        var all = snapshot?.providers ?? [];
        return all.filter(p => (p.id === "claude" && root.showClaude) || (p.id === "codex" && root.showCodex) || (p.id === "opencodeGo" && root.showGo));
    }

    function worstLevel(provider) {
        var worst = "ok";
        var windows = provider?.windows ?? [];
        for (var i = 0; i < windows.length; i++) {
            var level = levelOf(windows[i].usedPercent, root.warnAt, root.critAt);
            if (level === "crit")
                return "crit";
            if (level === "warn")
                worst = "warn";
            if (level === "unknown" && worst === "ok")
                worst = "unknown";
        }
        if (provider?.error)
            return "unknown";
        return worst;
    }

    function levelColor(level) {
        if (level === "crit")
            return Theme.error;
        if (level === "warn")
            return Theme.warning;
        return Theme.widgetTextColor;
    }

    function pillText(provider) {
        var code = shortCode(provider.id, "").provider;
        if (provider.error)
            return code + " –";
        var windows = provider.windows ?? [];
        if (windows.length === 0)
            return code + " …";
        var parts = [];
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i];
            parts.push(shortCode(provider.id, w.id).window + " " + pctText(w.usedPercent));
        }
        return code + " " + parts.join(" · ");
    }

    function updatedText() {
        var stamp = root.snapshot?.fetchedAt;
        if (!stamp)
            return "Waiting for first poll…";
        var ago = elapsed(stamp, root.headerNowMs);
        return ago === "just now" ? "Updated just now" : "Updated " + ago + " ago";
    }

    function countdown(resetsAt, nowMs) {
        if (!resetsAt)
            return "";
        var ms = new Date(resetsAt).getTime() - (nowMs ?? Date.now());
        if (!(ms > 0))
            return "soon";
        var mins = Math.ceil(ms / 60000);
        if (mins < 60)
            return mins + "m";
        var hours = Math.floor(mins / 60);
        var rest = mins - hours * 60;
        if (hours < 48)
            return rest === 0 ? hours + "h" : hours + "h " + rest + "m";
        var days = Math.floor(hours / 24);
        return days + "d " + (hours - days * 24) + "h";
    }

    // Inline formatting helpers: shared QML includes stay frozen at
    // shell startup (the plugin cache only revision-busts manifest
    // components), so per-surface formatting lives in each surface.
    // Threshold and merge rules stay in collectors/model.py.
    function shortCode(providerId, windowId) {
        var providers = {"claude": "Cl", "codex": "Cx", "opencodeGo": "Go"};
        return {"provider": providers[providerId] ?? providerId,
                "window": shortWindow(windowId)};
    }

    // Unknown window ids (e.g. future Claude scoped windows beyond the
    // observed weekly-fable) collapse to segment initials so the pill
    // stays compact instead of leaking a long id into the bar.
    function shortWindow(windowId) {
        var known = {"fiveHour": "5h", "rolling": "5h", "weekly": "W",
                     "monthly": "M", "weekly-fable": "F"};
        if (known[windowId])
            return known[windowId];
        var parts = String(windowId).split(/[^a-zA-Z0-9]+/);
        if (parts.length === 1 && parts[0].length > 1)
            return (parts[0][0] + parts[0][1]).toUpperCase();
        var code = "";
        for (var i = 0; i < parts.length && code.length < 2; i++) {
            if (parts[i].length > 0)
                code += parts[i][0].toUpperCase();
        }
        return code || windowId;
    }

    function pctText(percent) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "–";
        return Math.round(percent) + "%";
    }

    function levelOf(percent, warn, crit) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "unknown";
        if (percent >= crit)
            return "crit";
        if (percent >= warn)
            return "warn";
        return "ok";
    }

    function elapsed(isoString, nowMs) {
        if (!isoString)
            return "";
        var ms = (nowMs ?? Date.now()) - new Date(isoString).getTime();
        if (!(ms > 0))
            return "just now";
        var mins = Math.floor(ms / 60000);
        if (mins < 1)
            return "just now";
        if (mins < 60)
            return mins + "m";
        var hours = Math.floor(mins / 60);
        if (hours < 48)
            return hours + "h";
        return Math.floor(hours / 24) + "d";
    }

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingS

            Repeater {
                model: root.providers

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.pillText(modelData)
                    font.pixelSize: root.textSize
                    color: root.levelColor(root.worstLevel(modelData))
                }
            }

            StyledText {
                visible: root.providers.length === 0
                anchors.verticalCenter: parent.verticalCenter
                text: "AI …"
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: Theme.spacingXXS

            Repeater {
                model: root.providers

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.pillText(modelData)
                    font.pixelSize: root.textSize
                    color: root.levelColor(root.worstLevel(modelData))
                }
            }

            StyledText {
                visible: root.providers.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: "AI …"
                font.pixelSize: root.textSize
                color: Theme.widgetTextColor
            }
        }
    }

    popoutContent: Component {
        PopoutComponent {
            headerText: "AI Usage"
            detailsText: root.updatedText()

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Repeater {
                    model: root.providers
                    delegate: Column {
                        // One provider block: windows with bars, banked
                        // resets, or a one-line hint. (Duplicated per
                        // surface: shared includes don't hot-reload.)
                        property var provider: modelData
                        property double nowMs: Date.now()

                        function barColor(percent) {
                            var level = root.levelOf(percent, root.warnAt, root.critAt);
                            if (level === "crit")
                                return Theme.error;
                            if (level === "warn")
                                return Theme.warning;
                            return Theme.primary;
                        }

                        spacing: Theme.spacingS
                        width: parent.width

                        Timer {
                            interval: 60000
                            repeat: true
                            running: true
                            onTriggered: nowMs = Date.now()
                        }

                        Row {
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                text: provider?.name ?? ""
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                            }

                            StyledText {
                                visible: !!(provider?.plan)
                                text: provider?.plan ?? ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                visible: provider?.stale === true
                                text: "· last-known"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.warning
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        StyledText {
                            visible: !!(provider?.error)
                            width: parent.width
                            wrapMode: Text.WordWrap
                            text: provider?.error?.hint ?? ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        Repeater {
                            model: provider?.error ? [] : (provider?.windows ?? [])

                            Row {
                                spacing: Theme.spacingS

                                StyledText {
                                    width: 92
                                    elide: Text.ElideRight
                                    text: modelData.label ?? modelData.id
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceText
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledRect {
                                    width: 120
                                    height: 8
                                    radius: 4
                                    color: Theme.surfaceContainerHigh
                                    anchors.verticalCenter: parent.verticalCenter

                                    StyledRect {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width * Math.min(100, Math.max(0, modelData.usedPercent ?? 0)) / 100
                                        height: parent.height
                                        radius: parent.radius
                                        color: barColor(modelData.usedPercent)
                                    }
                                }

                                StyledText {
                                    text: root.pctText(modelData.usedPercent)
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Theme.fontWeightMedium
                                    color: barColor(modelData.usedPercent)
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                StyledText {
                                    visible: !!modelData.resetsAt
                                    text: "↻ " + root.countdown(modelData.resetsAt, nowMs)
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: Theme.surfaceVariantText
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }
                        }

                        Row {
                            visible: !!(provider && provider.resets)
                            width: parent.width
                            spacing: Theme.spacingS

                            StyledText {
                                text: (provider?.resets?.available ?? 0) > 0 ? (provider.resets.available + (provider.resets.available === 1 ? " reset available" : " resets available")) : "No resets banked"
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            DButton {
                                text: "Open usage page"
                                iconName: "open_in_new"
                                onClicked: {
                                    if (provider?.resets?.url)
                                        Qt.openUrlExternally(provider.resets.url);
                                }
                            }
                        }
                    }
                }

                DButton {
                    text: "Refresh now"
                    iconName: "refresh"
                    onClicked: refreshVar.set((refreshVar.value ?? 0) + 1)
                }
            }
        }
    }
    popoutWidth: 440
}
