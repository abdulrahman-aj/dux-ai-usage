import QtQuick
import qs.Common
import qs.DCommon.Widgets
import qs.Widgets
import qs.Modules.Plugins

// Desktop widget: one component that picks its layout from its own
// size, with +/-8px hysteresis on every threshold so dragging across
// a boundary never flickers.
//   tiny: exactly the bar pill (monochrome logo + one headline number
//     per provider, same headline rule/state colors/mark), in a row;
//     a column when tall and narrow. No header.
//   small: one compact line per provider: logo, headline number, thin
//     bars for each window (no labels/reset text).
//   large: the ProviderCard grid, 1-3 columns.
// Stale/rate-limited providers show last-known values; error
// providers headline "–" in the stale tint (unknown level) at every
// size. Minimum size is pill-sized; the default size lands in large.
DesktopPluginComponent {
    id: root

    minWidth: 76
    minHeight: 44
    property real defaultWidth: 440
    property real defaultHeight: 320

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
    readonly property real pad: Theme.spacingM + Theme.densityStepXS
    readonly property real gapS: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepXS)
    readonly property real minCard: 220 + Theme.densityStepM
    readonly property real smallW: 400 + Theme.densityStepM
    readonly property real smallH: 260 + Theme.densityStepM
    // Tiny thresholds stay fixed: pill sizes never move with density.
    property string layoutMode: "large"
    property bool tinyVertical: false

    function updateLayoutMode() {
        var w = root.width;
        var h = root.height;
        if (root.layoutMode === "tiny") {
            if (h > 88 && w > 148)
                root.layoutMode = (w >= root.smallW + 16 && h >= root.smallH + 16) ? "large" : "small";
        } else if (root.layoutMode === "small") {
            if (h <= 72 || w <= 132)
                root.layoutMode = "tiny";
            else if (w > root.smallW + 16 && h > root.smallH + 16)
                root.layoutMode = "large";
        } else {
            if (h <= 72 || w <= 132)
                root.layoutMode = "tiny";
            else if (w < root.smallW - 16 || h < root.smallH - 16)
                root.layoutMode = "small";
        }
        if (root.tinyVertical) {
            if (w > 168)
                root.tinyVertical = false;
        } else if (w <= 152) {
            root.tinyVertical = true;
        }
    }

    onWidthChanged: root.updateLayoutMode()
    onHeightChanged: root.updateLayoutMode()

    Component.onCompleted: {
        var w = root.width;
        var h = root.height;
        if (h <= 80 || w <= 140)
            root.layoutMode = "tiny";
        else if (w < root.smallW || h < root.smallH)
            root.layoutMode = "small";
        else
            root.layoutMode = "large";
        root.tinyVertical = w <= 160;
    }

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
    }

    // Content scrolls inside the painted area (clipped) so a small
    // size never paints cards onto the desktop.
    Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.paintedHeight
        anchors.margins: root.pad
        clip: true
        contentWidth: width
        contentHeight: body.implicitHeight

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
            }

            // Tiny: the bar pill, centered. Row normally, column when
            // tall and narrow. (Separate Row/Column: a Flow sized to
            // its implicitWidth collapses and wraps the pill rows.)
            Row {
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

                StyledText {
                    visible: root.providers.length === 0
                    anchors.verticalCenter: parent.verticalCenter
                    text: "AI …"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
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

                StyledText {
                    visible: root.providers.length === 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "AI …"
                    font.pixelSize: Theme.fontSizeMedium
                    color: Theme.surfaceText
                }
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
                            // Font-derived, so no density step (fonts never
                            // move with density): must fit "100%" at every
                            // density.
                            width: Theme.buttonHeightXS + Theme.spacingXS
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
                            text: u.shortMark(headline?.id)
                            font.pixelSize: Math.max(Theme.fontSizeXSmall + Theme.densityStepXS, Math.round(Theme.fontSizeMedium * 0.62))
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
                                    height: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepXS)
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

                readonly property real minCard: root.minCard
                readonly property int cols: Math.min(3, Math.max(1, Math.floor((width + spacing) / (minCard + spacing))))
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
