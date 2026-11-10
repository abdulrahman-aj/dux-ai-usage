import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash

// Roomy per-provider view: bars, reset times, plan, banked resets.
DashTabComponent {
    id: root

    property double headerNowMs: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: root.live
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

    // Inline (see Widget.qml): elapsed-time text for the header.
    function updatedText() {
        var stamp = root.snapshot?.fetchedAt;
        if (!stamp)
            return "Waiting for first poll…";
        var ago = elapsed(stamp, root.headerNowMs);
        return ago === "just now" ? "Updated just now" : "Updated " + ago + " ago";
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

    // Inline formatting helpers (see Widget.qml): shared QML includes
    // stay frozen at shell startup, so per-surface formatting lives here.
    function levelOf(percent, warn, crit) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "unknown";
        if (percent >= crit)
            return "crit";
        if (percent >= warn)
            return "warn";
        return "ok";
    }

    function pctText(percent) {
        if (percent === null || percent === undefined || isNaN(percent))
            return "–";
        return Math.round(percent) + "%";
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

    implicitHeight: Math.max(DashMetrics.tabMinHeight, content.implicitHeight + Theme.spacingL * 2)
    menuActions: [
        {
            label: "Refresh now",
            iconName: "refresh",
            action: () => refreshVar.set((refreshVar.value ?? 0) + 1)
        }
    ]

    Column {
        id: content
        width: parent.width
        spacing: Theme.spacingL

        Row {
            width: parent.width
            spacing: Theme.spacingM

            StyledText {
                text: root.updatedText()
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                anchors.verticalCenter: parent.verticalCenter
            }

            DButton {
                text: "Refresh now"
                iconName: "refresh"
                anchors.verticalCenter: parent.verticalCenter
                onClicked: refreshVar.set((refreshVar.value ?? 0) + 1)
            }
        }

        Repeater {
            model: root.providers
            delegate: Column {
                // Same provider block as the bar popout, roomier bars.
                // Duplicated: shared includes don't hot-reload (see Widget.qml).
                property var provider: modelData
                property double nowMs: Date.now()

                spacing: Theme.spacingS
                width: parent.width

                Timer {
                    interval: 60000
                    repeat: true
                    running: root.live
                    onTriggered: nowMs = Date.now()
                }

                function barColor(percent) {
                    var level = root.levelOf(percent, root.warnAt, root.critAt);
                    if (level === "crit")
                        return Theme.error;
                    if (level === "warn")
                        return Theme.warning;
                    return Theme.primary;
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    StyledText {
                        text: provider?.name ?? ""
                        font.pixelSize: Theme.fontSizeLarge
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
                            width: 110
                            elide: Text.ElideRight
                            text: modelData.label ?? modelData.id
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledRect {
                            width: 220
                            height: 10
                            radius: 5
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

        StyledText {
            visible: root.providers.length === 0
            text: root.snapshot ? "All providers are disabled in settings." : "Waiting for the first poll (up to a few minutes after enabling)…"
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
        }
    }
}
