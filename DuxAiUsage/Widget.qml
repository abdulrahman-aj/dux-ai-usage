import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import "Format.js" as Format

// Bar pill (both orientations) + popout: per-provider compact windows,
// colored by thresholds. One shared poller lives in Daemon.qml; this
// surface only reads the "duxAiSnapshot" global var.
PluginComponent {
    id: root

    property var popoutService: null

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
            var level = Format.levelOf(windows[i].usedPercent, root.warnAt, root.critAt);
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
        var code = Format.shortCode(provider.id, "").provider;
        if (provider.error)
            return code + " –";
        var windows = provider.windows ?? [];
        if (windows.length === 0)
            return code + " …";
        var parts = [];
        for (var i = 0; i < windows.length; i++) {
            var w = windows[i];
            parts.push(Format.shortCode(provider.id, w.id).window + " " + Format.pctText(w.usedPercent));
        }
        return code + " " + parts.join(" · ");
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
            detailsText: root.snapshot?.fetchedAt ? ("Updated " + Format.countdown(root.snapshot.fetchedAt, Date.now()) + " ago") : "Waiting for first poll…"

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Repeater {
                    model: root.providers
                    delegate: ProviderSection {
                        provider: modelData
                        warn: root.warnAt
                        crit: root.critAt
                        barWidth: 120
                        openUrl: url => Qt.openUrlExternally(url)
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
