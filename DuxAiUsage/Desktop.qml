import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins

// Desktop widget: the same provider cards as the dash tab, sized to
// the widget rectangle (cards wrap/stack when narrow).
DesktopPluginComponent {
    id: root

    minWidth: 220
    minHeight: 160

    property double nowMs: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
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

    readonly property var snapshot: snapshotVar.value
    readonly property var providers: u.visibleProviders(root.snapshot, root.pluginData)

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: Theme.cardSurface ?? Theme.surfaceContainerHigh
        opacity: 0.92
    }

    // Content scrolls inside the fixed rectangle (clipped) so a small
    // default size never paints cards onto the desktop.
    Flickable {
        anchors.fill: parent
        anchors.margins: Theme.spacingM
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight

        Column {
            id: body
            width: parent.width
            spacing: Theme.spacingS

            Row {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    text: "AI Usage"
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                    anchors.verticalCenter: parent.verticalCenter
                }

                StyledText {
                    text: u.updatedText(root.snapshot?.fetchedAt, root.nowMs)
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Flow {
                id: cardFlow
                width: parent.width
                spacing: Theme.spacingS

                readonly property int cols: width < 380 ? 1 : 2
                readonly property real cardWidth: (width - (cols - 1) * spacing) / cols

                Repeater {
                    model: root.providers
                    delegate: ProviderCard {
                        width: cardFlow.cardWidth
                        provider: modelData
                        nowMs: root.nowMs
                        fetchedAt: root.snapshot?.fetchedAt ?? ""
                        warnAt: root.warnAt
                        critAt: root.critAt
                    }
                }
            }

            StyledText {
                visible: root.providers.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.snapshot ? "All providers are disabled in settings." : "Waiting for the first poll (up to a few minutes after enabling)…"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
