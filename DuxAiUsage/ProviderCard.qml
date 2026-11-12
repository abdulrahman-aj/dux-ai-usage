import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One provider card: logo + name + plan + headline percent in the
// header, per-window gauges with reset countdowns, banked-resets note.
// The usage-page link lives as a small icon button in the header (not
// a row). Used by the dash tab grid, the popout and the desktop widget
// alike (same component, sized by its rectangle); the parent sets
// width, the host lays cards out in its own flow grid.
StyledRect {
    id: root

    property var provider: null
    property double nowMs: Date.now()
    property real warnAt: 80
    property real critAt: 100
    property var onOpenUsage: null

    AiUsageShared {
        id: u
    }

    readonly property var headline: u.headlineWindow(root.provider)
    readonly property string headlineLevel: u.headlineLevel(root.provider, tc[0], tc[1])
    readonly property color headlineColor: u.stateColor(root.headlineLevel)
    readonly property var tc: u.clampedThresholds(root.warnAt, root.critAt)
    readonly property string updatedLine: u.providerUpdatedText(root.provider, root.nowMs)
    readonly property string resetsLine: u.resetsLine(root.provider, root.nowMs)
    readonly property string usageLink: u.providerLink(root.provider)

    color: Theme.cardSurface ?? Theme.surfaceContainerHigh
    radius: Theme.cornerRadius

    // Compact card: tight padding and gaps, same information.
    readonly property real pad: Theme.spacingXS
    readonly property real gapS: Theme.spacingXXS

    implicitHeight: body.implicitHeight + pad * 2

    Column {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: pad
        spacing: gapS

        Item {
            id: headerRow
            width: parent.width
            height: Math.max(logoIcon.implicitHeight, nameText.implicitHeight, headlinePct.implicitHeight, openBtn.visible ? openBtn.implicitHeight : 0)

            DSVGIcon {
                id: logoIcon
                source: u.logoFor(root.provider?.id)
                size: Math.max(Theme.iconSizeSmall, Theme.iconSizeSmall + Theme.spacingXXS + Theme.densityStepXS)
                colorOverride: Theme.surfaceText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                id: nameText
                anchors.left: logoIcon.right
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: root.provider?.name ?? ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Theme.fontWeightMedium
                color: Theme.surfaceText
            }

            StyledText {
                id: planText
                anchors.left: nameText.right
                anchors.leftMargin: Theme.spacingXS
                anchors.right: headlineGroup.visible ? headlineGroup.left : (openBtn.visible ? openBtn.left : parent.right)
                anchors.rightMargin: headlineGroup.visible ? Theme.spacingXS : (openBtn.visible ? gapS : 0)
                anchors.verticalCenter: parent.verticalCenter
                visible: !!(root.provider?.plan)
                elide: Text.ElideRight
                text: root.provider?.plan ?? ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            DActionButton {
                id: openBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: root.usageLink !== ""
                iconName: "open_in_new"
                tooltipText: "Open usage page"
                onClicked: {
                    Qt.openUrlExternally(root.usageLink);
                    if (root.onOpenUsage && typeof root.onOpenUsage === "function")
                        root.onOpenUsage();
                }
            }

            Row {
                id: headlineGroup
                visible: root.headline !== null
                anchors.right: openBtn.visible ? openBtn.left : parent.right
                anchors.rightMargin: openBtn.visible ? gapS : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                StyledText {
                    id: headlinePct
                    anchors.verticalCenter: parent.verticalCenter
                    text: u.pctText(root.headline?.usedPercent)
                    font.pixelSize: Theme.fontSizeMedium
                    font.weight: Theme.fontWeightMedium
                    color: root.headlineColor
                }

                StyledText {
                    visible: root.provider?.headlineShort === true
                    anchors.verticalCenter: parent.verticalCenter
                    text: u.shortMark(root.headline?.id)
                    font.pixelSize: Theme.fontSizeSmall
                    color: root.headlineColor
                    opacity: 0.85
                }
            }
        }

        StyledText {
            visible: root.updatedLine !== ""
            width: parent.width
            elide: Text.ElideRight
            text: root.updatedLine
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        StyledText {
            visible: !!(root.provider?.error)
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.provider?.error?.hint ?? ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        Repeater {
            model: root.provider?.error ? [] : (root.provider?.windows ?? [])

            WindowRow {
                width: parent.width
                win: modelData
                nowMs: root.nowMs
                warnAt: root.tc[0]
                critAt: root.tc[1]
            }
        }

        StyledText {
            visible: root.resetsLine !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: root.resetsLine
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }
}
