import QtQuick
import qs.Common
import qs.DCommon.Widgets

// One usage-window meter: label on the left, percent and reset
// countdown on the right, a thin track below. Shared by every
// ProviderCard so all surfaces meter a window identically; the parent
// sets width.
Item {
    id: root

    property var win: null
    property double nowMs: Date.now()
    property real warnAt: 80
    property real critAt: 100

    AiUsageShared {
        id: u
    }

    readonly property string countdownText: root.win?.resetsAt ? u.countdown(root.win.resetsAt, root.nowMs) : ""
    readonly property color levelColor: u.stateColor(u.levelOf(root.win?.usedPercent, root.warnAt, root.critAt))

    implicitHeight: topRow.height + Theme.spacingXS + bar.height

    Item {
        id: topRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Math.max(labelText.implicitHeight, pctText.implicitHeight)

        StyledText {
            id: labelText
            anchors.left: parent.left
            anchors.right: rightGroup.left
            anchors.rightMargin: Theme.spacingS
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
            spacing: Theme.spacingS

            // Reserved "100%" width keeps the percents of every row in
            // one right-aligned column, like Dux's own numeric readouts.
            NumericText {
                id: pctText
                anchors.verticalCenter: parent.verticalCenter
                reserveText: "100%"
                horizontalAlignment: Text.AlignRight
                text: u.pctText(root.win?.usedPercent)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Theme.fontWeightMedium
                color: root.levelColor
            }

            Row {
                visible: root.countdownText !== ""
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXXS

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "schedule"
                    size: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.countdownText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    Rectangle {
        id: bar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: topRow.bottom
        anchors.topMargin: Theme.spacingXS
        height: u.meterHeight
        radius: height / 2
        color: u.meterTrack

        Rectangle {
            width: Math.max(0, parent.width * Math.min(100, Math.max(0, root.win?.usedPercent ?? 0)) / 100)
            height: parent.height
            radius: parent.radius
            color: root.levelColor
        }
    }
}
