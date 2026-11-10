import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Modules.Plugins
import qs.Modules.DDash
import "Format.js" as Format

// Roomy per-provider view: bars, reset times, plan, banked resets.
DashTabComponent {
    id: root

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
                text: root.snapshot?.fetchedAt ? ("Updated " + Format.countdown(root.snapshot.fetchedAt, Date.now()) + " ago") : "Waiting for first poll…"
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
            delegate: ProviderSection {
                provider: modelData
                warn: root.warnAt
                crit: root.critAt
                barWidth: 220
                openUrl: url => Qt.openUrlExternally(url)
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
