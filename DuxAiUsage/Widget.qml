import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins

// Bar pill (both orientations) + popout: monochrome logo + headline
// number per provider, the number colored by the shared state rule.
// The popout reuses the same ProviderCard as the dash tab and desktop
// widget. One shared poller lives
// in Daemon.qml; this surface only reads the "duxAiSnapshot" global
// var. Formatting lives in AiUsageShared.qml (single copy); threshold
// and headline rules live in collectors/model.py (unit-tested).
PluginComponent {
    id: root

    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100
    readonly property var tc: u.clampedThresholds(root.warnAt, root.critAt)

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

    horizontalBarPill: Component {
        // Bar-stable: fixed tokens, no density steps (the bar itself
        // never moves with density).
        Row {
            spacing: Theme.spacingS

            Repeater {
                model: root.providers

                PillRow {
                    provider: modelData
                    warnAt: root.warnAt
                    critAt: root.critAt
                    textSize: root.textSize
                    anchors.verticalCenter: parent.verticalCenter
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
            spacing: Theme.spacingXS

            Repeater {
                model: root.providers

                PillRow {
                    provider: modelData
                    warnAt: root.warnAt
                    critAt: root.critAt
                    textSize: root.textSize
                    anchors.horizontalCenter: parent.horizontalCenter
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
            id: popout
            headerText: "AI Usage"
            detailsText: u.updatedText(root.snapshot?.fetchedAt, popoutBody.nowMs)
            headerActions: DActionButton {
                iconName: "refresh"
                tooltipText: "Refresh now"
                onClicked: refreshVar.set((refreshVar.value ?? 0) + 1)
            }

            Column {
                id: popoutBody
                property double nowMs: Date.now()

                Timer {
                    interval: 60000
                    repeat: true
                    running: true
                    onTriggered: popoutBody.nowMs = Date.now()
                }

                // Popout gaps follow density like other popout surfaces.
                readonly property real popGap: Math.max(Theme.spacingS, Theme.spacingM + Theme.densityStepS)

                width: parent.width
                spacing: popGap

                Repeater {
                    model: root.providers
                    delegate: ProviderCard {
                        width: parent.width
                        provider: modelData
                        nowMs: popoutBody.nowMs
                        fetchedAt: root.snapshot?.fetchedAt ?? ""
                        warnAt: root.tc[0]
                        critAt: root.tc[1]
                        onOpenUsage: function() {
                            if (popout && typeof popout.closePopout === "function")
                                popout.closePopout();
                        }
                    }
                }
            }
        }
    }
    // Fixed default size like Dux's own widgets (density applies to
    // live content metrics, not to stored defaults).
    popoutWidth: 440
}
