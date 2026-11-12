import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.DDash
import qs.Modules.Plugins

// Desktop widget: one component that picks its layout from its own
// size. Tapping it opens the AI Usage dash tab while that tab is
// selectable (otherwise the tap does nothing); Refresh and "Open
// usage page" keep their own actions, and dragging still scrolls.
//   tiny: exactly the bar pill (monochrome logo + one headline number
//     per provider, same headline rule/state colors/mark), in a row;
//     a column when the row does not fit. No header.
//   small: one compact line per provider: logo, headline number, thin
//     bars for each window (no labels/reset text).
//   large: the ProviderCard grid, 1–3 columns.
// Stale/rate-limited providers show last-known values; error
// providers headline "–" in the stale tint (unknown level) at every
// size. Minimum size (76x44) fits a single-provider pill; more
// providers need ~240px of width for a row or ~100px of height for a
// column — below that the painted area clips, like an overfull bar
// pill. The default size lands in small: one compact line per provider.
DesktopPluginComponent {
    id: root

    minWidth: 76
    minHeight: 44
    property real defaultWidth: 360
    property real defaultHeight: 260

    property double nowMs: Date.now()

    Timer {
        interval: 60000
        repeat: true
        running: true
        onTriggered: root.nowMs = Date.now()
    }

    readonly property real warnAt: pluginData.warnThreshold ?? 80
    readonly property real critAt: pluginData.critThreshold ?? 100

    // Density-aware metrics (Dux pattern: bar tokens stay fixed while
    // surfaces add density steps with floors).
    readonly property real pad: Theme.spacingS + Theme.densityStepXS
    readonly property real gapS: Math.max(Theme.spacingXXS, Theme.spacingXS + Theme.densityStepXS)
    readonly property real minCard: 220 + Theme.densityStepM
    readonly property real smallW: 400 + Theme.densityStepM
    readonly property real smallH: 260 + Theme.densityStepM

    // Headline slot fits "100%" at any fontScale (measured from the
    // headline font, like PillRow's font-derived mark floor): a fixed
    // token would clip at large text sizes and paint into the bars.
    TextMetrics {
        id: headFontMetrics
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Theme.fontWeightMedium
        text: "100%"
    }
    readonly property real headSlotW: Math.ceil(headFontMetrics.advanceWidth) + Theme.spacingXS
    // Layout follows the widget's own size directly. The size is set
    // by Dux geometry, never by content, so no feedback loop or
    // jitter is possible — like Dux's own SystemMonitorWidget, plain
    // width/height thresholds are enough. Tiny thresholds stay fixed
    // (pill sizes never move with density); small/large move with it.
    // Orientation within tiny is content-derived (measured row width
    // vs available width), so a narrow widget never clips a row
    // mid-provider; orientation cannot feed back into the measured
    // width, so it cannot oscillate either.
    readonly property string layoutMode: (root.height <= 80 || root.width <= 140) ? "tiny" : (root.width < root.smallW || root.height < root.smallH) ? "small" : "large"
    readonly property bool tinyVertical: tinyRow.implicitWidth > root.width - root.pad * 2

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

    // The dash tab id (DashRegistry.pluginPrefix + pluginId). Clicks
    // open it only while it is selectable (plugin loaded and the tab
    // enabled in Settings → Dashboard); otherwise they do nothing, so a
    // hidden tab never yanks the user to the overview fallback.
    readonly property bool dashAvailable: DashRegistry.isSelectable(DashRegistry.pluginPrefix + root.pluginId)

    function openDashTab() {
        if (root.dashAvailable)
            PopoutService.openDankDash(DashRegistry.pluginPrefix + root.pluginId);
    }

    // Paint only as tall as the content: the window itself stays
    // user-sized, but no empty card area hangs under short content.
    readonly property real paintedHeight: Math.min(parent.height, body.implicitHeight + root.pad * 2)

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.paintedHeight
        radius: Theme.cornerRadius
        color: Theme.cardSurface ?? Theme.surfaceContainerHigh
        opacity: 0.92

        // Widget click opens the AI Usage dash tab (when available).
        // Below the Flickable, so it catches the padded margins; a second
        // tap area inside the Flickable covers the content itself.
        MouseArea {
            anchors.fill: parent
            enabled: root.dashAvailable
            cursorShape: root.dashAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.openDashTab()
        }
    }

    // Content scrolls inside the painted area (clipped) so a small
    // size never paints cards onto the desktop. The viewport ends at
    // the window edge when scrolling (bottom breathing room comes
    // from the padded content height), and hugs the content when not.
    Flickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.min(parent.height - root.pad, body.implicitHeight + root.pad)
        anchors.margins: root.pad
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight + root.pad

        // Tap area for the whole content: below the cards, so Refresh
        // and "Open usage page" keep their own actions. A tap opens the
        // dash tab; a drag still scrolls (the Flickable steals the
        // gesture mid-move and the tap never fires).
        MouseArea {
            width: flick.contentWidth
            height: flick.contentHeight
            enabled: root.dashAvailable
            cursorShape: root.dashAvailable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: root.openDashTab()
        }

        Column {
            id: body
            width: parent.width
            spacing: root.gapS

            Row {
                visible: root.layoutMode !== "tiny"
                width: parent.width
                spacing: root.gapS

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

                DActionButton {
                    iconName: "refresh"
                    tooltipText: "Refresh now"
                    anchors.verticalCenter: parent.verticalCenter
                    onClicked: refreshVar.set((refreshVar.value ?? 0) + 1)
                }
            }

            // Tiny: the bar pill, centered. Horizontal when the measured
            // row fits, column otherwise (never a clipped row).
            // Separate Row/Column: a Flow sized to its implicitWidth
            // collapses and wraps the pill rows.
            Row {
                id: tinyRow
                visible: root.layoutMode === "tiny" && !root.tinyVertical
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.gapS

                Repeater {
                    model: root.providers

                    PillRow {
                        provider: modelData
                        warnAt: root.warnAt
                        critAt: root.critAt
                        textSize: Theme.fontSizeMedium
                        logoColor: Theme.surfaceText
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Column {
                visible: root.layoutMode === "tiny" && root.tinyVertical
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: root.gapS

                Repeater {
                    model: root.providers

                    PillRow {
                        provider: modelData
                        warnAt: root.warnAt
                        critAt: root.critAt
                        textSize: Theme.fontSizeMedium
                        logoColor: Theme.surfaceText
                        anchors.horizontalCenter: parent.horizontalCenter
                    }
                }
            }

            StyledText {
                visible: root.layoutMode === "tiny" && root.providers.length === 0
                anchors.horizontalCenter: parent.horizontalCenter
                text: "AI …"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
            }

            // Small: one compact line per provider. The bars reuse the
            // shared level/state rule; no labels or reset text.
            Column {
                visible: root.layoutMode === "small"
                width: parent.width
                spacing: root.gapS

                Repeater {
                    model: root.providers

                    Item {
                        width: parent.width
                        height: Math.max(sLogo.height, sHead.height, barsCol.height)

                        property var prov: modelData
                        readonly property var headline: u.headlineWindow(prov)
                        readonly property var stc: u.clampedThresholds(root.warnAt, root.critAt)
                        readonly property string level: u.headlineLevel(prov, stc[0], stc[1])
                        readonly property color hcolor: u.stateColor(level)

                        DSVGIcon {
                            id: sLogo
                            source: u.logoFor(prov?.id)
                            size: Theme.iconSizeSmall + Theme.densityStepXS
                            colorOverride: Theme.surfaceText
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        StyledText {
                            id: sHead
                            anchors.left: sLogo.right
                            anchors.leftMargin: root.gapS
                            anchors.verticalCenter: parent.verticalCenter
                            // Fixed slot keeps every provider's bars aligned.
                            width: root.headSlotW
                            elide: Text.ElideRight
                            text: u.pctText(headline?.usedPercent)
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: Theme.fontWeightMedium
                            color: hcolor
                        }

                        StyledText {
                            id: sMark
                            visible: prov?.headlineShort === true
                            anchors.left: sHead.right
                            anchors.leftMargin: Theme.spacingXXS
                            anchors.top: parent.top
                            anchors.topMargin: Theme.spacingXXS / 2
                            text: u.shortMark(headline?.id)
                            font.pixelSize: Math.max(Theme.fontSizeXSmall, Math.round(Theme.fontSizeMedium * 0.62))
                            color: hcolor
                            opacity: 0.85
                        }

                        Column {
                            id: barsCol
                            anchors.left: sMark.visible ? sMark.right : sHead.right
                            anchors.leftMargin: root.gapS
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXXS

                            Repeater {
                                model: prov?.error ? [] : (prov?.windows ?? [])

                                StyledRect {
                                    width: parent.width
                                    height: Math.max(6, Theme.spacingXS + Theme.densityStepXS)
                                    radius: height / 2
                                    color: Theme.surfaceContainerHigh

                                    StyledRect {
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Math.max(0, parent.width * Math.min(100, Math.max(0, modelData?.usedPercent ?? 0)) / 100)
                                        height: parent.height
                                        radius: parent.radius
                                        color: u.stateColor(u.levelOf(modelData?.usedPercent, stc[0], stc[1]))
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Flow {
                id: cardFlow
                visible: root.layoutMode === "large"
                width: parent.width
                spacing: root.gapS

                readonly property int cols: Math.min(3, Math.max(1, Math.floor((width + spacing) / (root.minCard + spacing))))
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
                visible: (root.layoutMode !== "tiny") && root.providers.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: root.snapshot ? "All providers are disabled in settings." : "Waiting for the first poll (up to a few minutes after enabling)…"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
