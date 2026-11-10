import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins

// Bar pill (both orientations) + popout: logo + headline number per
// provider, colored by the shared state rule. One shared poller lives
// in Daemon.qml; this surface only reads the "duxAiSnapshot" global
// var. Formatting lives in AiUsageShared.qml (single copy); threshold
// and headline rules live in collectors/model.py (unit-tested).
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
            headerText: "AI Usage"
            detailsText: u.updatedText(root.snapshot?.fetchedAt, root.headerNowMs)

            Column {
                width: parent.width
                spacing: Theme.spacingM

                Repeater {
                    model: root.providers
                    delegate: Column {
                        // One provider block: logo + headline, window
                        // gauges, quiet/prominent usage link.
                        property var provider: modelData
                        property double nowMs: Date.now()
                        readonly property var headline: u.headlineWindow(provider, root.tc[0], root.tc[1])
                        readonly property string level: u.headlineLevel(provider, root.tc[0], root.tc[1])
                        readonly property color state: u.stateColor(level)

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

                            DSVGIcon {
                                source: u.logoFor(provider?.id)
                                size: 16
                                colorOverride: state
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                text: provider?.name ?? ""
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Theme.fontWeightMedium
                                color: Theme.surfaceText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                visible: !!(provider?.plan)
                                text: provider?.plan ?? ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                visible: u.staleText(provider, root.snapshot?.fetchedAt, nowMs) !== ""
                                text: u.staleText(provider, root.snapshot?.fetchedAt, nowMs)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.warning
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        Row {
                            visible: !provider?.error && !!headline
                            spacing: Theme.spacingXS

                            StyledText {
                                text: u.pctText(headline?.usedPercent)
                                font.pixelSize: Theme.fontSizeLarge + 4
                                font.weight: Theme.fontWeightMedium
                                color: state
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            StyledText {
                                visible: u.isShortTakeover(provider)
                                text: u.shortMark(headline?.id)
                                font.pixelSize: Theme.fontSizeSmall
                                color: state
                                opacity: 0.85
                                anchors.top: parent.top
                                anchors.topMargin: 2
                            }

                            StyledText {
                                visible: !!(headline?.label)
                                text: headline?.label ?? ""
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
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

                            WindowRow {
                                width: parent.width
                                win: modelData
                                nowMs: nowMs
                                warnAt: root.tc[0]
                                critAt: root.tc[1]
                            }
                        }

                        UsageRow {
                            width: parent.width
                            provider: parent.provider
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
