import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One usage-window gauge: label, percent and reset on ONE line above
// a thin bar. Shared by the popout list and the provider cards so every
// surface meters a window identically. One text line + bar fits any card
// width down to a narrow desktop widget; the parent sets width.
Item {
    id: root

    property var win: null
    property double nowMs: Date.now()
    property real warnAt: 80
    property real critAt: 100

    AiUsageShared {
        id: u
    }

    readonly property string countdownText: root.win?.resetsAt ? "↻ " + u.countdown(root.win.resetsAt, root.nowMs) : ""
    readonly property color levelColor: u.stateColor(u.levelOf(root.win?.usedPercent, root.warnAt, root.critAt))

    // Thin track shared with the desktop widget's small-mode bars.
    readonly property real barH: u.thinBarHeight
    readonly property real gapXS: 2
    readonly property real gapS: Theme.spacingXXS
    readonly property real gapM: Theme.spacingXS

    implicitHeight: topRow.height + gapXS + bar.height

    Item {
        id: topRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(labelText.implicitHeight, pctText.implicitHeight, sepText.implicitHeight, cdText.implicitHeight)

        StyledText {
            id: labelText
            anchors.left: parent.left
            anchors.right: rightGroup.left
            anchors.rightMargin: root.gapM
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.win?.label ?? root.win?.id ?? ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
        }

        Row {
            id: rightGroup
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: gapS

            StyledText {
                id: pctText
                anchors.verticalCenter: parent.verticalCenter
                text: u.pctText(root.win?.usedPercent)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.levelColor
            }

            StyledText {
                id: sepText
                anchors.verticalCenter: parent.verticalCenter
                visible: cdText.visible
                text: "·"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                id: cdText
                anchors.verticalCenter: parent.verticalCenter
                visible: root.countdownText !== ""
                text: root.countdownText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    StyledRect {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topRow.bottom
        anchors.topMargin: gapXS
        height: barH
        radius: barH / 2
        color: Theme.surfaceContainerHigh

        StyledRect {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: Math.max(0, parent.width * Math.min(100, Math.max(0, root.win?.usedPercent ?? 0)) / 100)
            height: parent.height
            radius: parent.radius
            color: root.levelColor
        }
    }
}
