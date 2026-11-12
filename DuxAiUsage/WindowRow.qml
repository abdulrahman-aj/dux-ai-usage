import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One usage-window gauge row: label + reset countdown on top, bar +
// percent below. Shared by the popout list and the provider cards so
// every surface meters a window identically. Two lines so the row fits
// any card width down to a narrow desktop widget; the parent sets
// width and the bar takes what is left.
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

    // Track height follows density with a floor so dense never collapses.
    readonly property real barH: Math.max(Theme.spacingXS, Theme.spacingS + Theme.densityStepXS)
    readonly property real gapXS: Math.max(2, Theme.spacingXXS + Theme.densityStepXS)
    readonly property real gapS: Math.max(Theme.spacingXXS, Theme.spacingXS + Theme.densityStepXS)

    implicitHeight: topRow.height + gapXS + bottomRow.height

    Item {
        id: topRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(labelText.implicitHeight, cdText.implicitHeight)

        StyledText {
            id: labelText
            anchors.left: parent.left
            anchors.right: cdText.left
            anchors.rightMargin: cdText.visible ? gapS : 0
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: root.win?.label ?? root.win?.id ?? ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
        }

        StyledText {
            id: cdText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: root.countdownText !== ""
            text: root.countdownText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    Item {
        id: bottomRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topRow.bottom
        anchors.topMargin: gapXS
        height: Math.max(pctText.implicitHeight, barH)

        StyledRect {
            anchors.left: parent.left
            anchors.right: pctText.left
            anchors.rightMargin: gapS
            anchors.verticalCenter: parent.verticalCenter
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

        StyledText {
            id: pctText
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: u.pctText(root.win?.usedPercent)
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Theme.fontWeightMedium
            color: root.levelColor
        }
    }
}
