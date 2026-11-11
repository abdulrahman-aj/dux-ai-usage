import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins

// Roomy provider cards in a grid: one card per provider, filling the
// tab width (cards wrap when narrow). Same ProviderCard component as
// the desktop widget.
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

    AiUsageShared {
        id: u
    }

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
    readonly property var providers: u.visibleProviders(root.snapshot, root.pluginData)

    // Tab padding/gaps follow density like other settings surfaces.
    readonly property real padL: Theme.spacingL + Theme.densityStepXS
    readonly property real gapM: Math.max(Theme.spacingS, Theme.spacingM + Theme.densityStepXS)

    // Size to the content: no reserved empty area under the cards.
    implicitHeight: content.implicitHeight + padL * 2
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
        spacing: gapM

        Row {
            width: parent.width
            spacing: gapM

            StyledText {
                text: u.updatedText(root.snapshot?.fetchedAt, root.headerNowMs)
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

        Flow {
            id: cardFlow
            width: parent.width
            spacing: gapM

            // Breakpoints follow density: denser fits more columns sooner.
            readonly property int cols: width < 460 + Theme.densityStepM ? 1 : width < 760 + Theme.densityStepM ? 2 : 3
            readonly property real cardWidth: (width - (cols - 1) * spacing) / cols

            Repeater {
                model: root.providers
                delegate: ProviderCard {
                    width: cardFlow.cardWidth
                    provider: modelData
                    nowMs: root.headerNowMs
                    fetchedAt: root.snapshot?.fetchedAt ?? ""
                    warnAt: root.warnAt
                    critAt: root.critAt
                    onOpenUsage: function() {
                        var host = root.dashHost;
                        if (host && typeof host.close === "function")
                            host.close();
                        else if (host)
                            host.dashVisible = false;
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
